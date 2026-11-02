import CoreGraphics
import Foundation

enum DragMotionEventMapper {
    static let tapLocation: CGEventTapLocation = .cghidEventTap

    static func accepts(_ type: CGEventType) -> Bool {
        if type == .mouseMoved { return true }
        return type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
    }

    static var eventMask: CGEventMask {
        let motionTypes: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        return motionTypes.reduce(
            CGEventMask(1) << CGEventType.scrollWheel.rawValue
        ) { $0 | (CGEventMask(1) << $1.rawValue) }
    }

    static func eventType(for button: CompoundTapButton) -> CGEventType {
        button == .right ? .rightMouseDragged : .leftMouseDragged
    }

    static func buttonNumber(for button: CompoundTapButton) -> Int64 {
        Int64(button == .right ? CGMouseButton.right.rawValue : CGMouseButton.left.rawValue)
    }

    static let postLocation: CGEventTapLocation = .cgSessionEventTap
}

/// A single source pairs the down/move/up events of a modern drag. Explicitly
/// allow hardware input during a synthetic drag; otherwise Quartz can suppress
/// the very mouse movement that must be converted into dragged events.
final class DragMouseEventFactory {
    let source: CGEventSource?
    init() {
        source = CGEventSource(stateID: .privateState)
        if let source {
            source.localEventsSuppressionInterval = 0
            let allowedEvents: CGEventFilterMask = [
                .permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents
            ]
            source.setLocalEventsFilterDuringSuppressionState(allowedEvents, state: .eventSuppressionStateSuppressionInterval)
            source.setLocalEventsFilterDuringSuppressionState(allowedEvents, state: .eventSuppressionStateRemoteMouseDrag)
        }
    }

    var isAvailable: Bool { source != nil }

    func buttonEvent(isDown: Bool, at location: CGPoint, button: CompoundTapButton, clickCount: Int64) -> CGEvent? {
        let type: CGEventType = button == .right
            ? (isDown ? .rightMouseDown : .rightMouseUp)
            : (isDown ? .leftMouseDown : .leftMouseUp)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button == .right ? .right : .left
        ) else { return nil }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        return event
    }

    /// Hammerspoon creates a new mouse event for each drag position and posts
    /// it at the session tap. Do not mutate the physical HID motion event.
    func freshDragEvent(from motion: CGEvent, button: CompoundTapButton, clickCount: Int64) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: DragMotionEventMapper.eventType(for: button),
            mouseCursorPosition: motion.location,
            mouseButton: button == .right ? .right : .left
        ) else { return nil }
        event.flags = motion.flags
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        return event
    }
}

/// Converts physical mouse movement during drag and suppresses the ordinary
/// scroll events Magic Mouse may emit while MouseToucher is recognizing pinch.
final class DragEventMonitor {
    private struct ActiveDrag {
        let button: CompoundTapButton
        let clickCount: Int64
    }

    private let stateLock = NSLock()
    private var activeDrag: ActiveDrag?
    private var suppressesScroll = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventFactory = DragMouseEventFactory()

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard eventFactory.isAvailable else { return false }

        guard let eventTap = CGEvent.tapCreate(
            tap: DragMotionEventMapper.tapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: DragMotionEventMapper.eventMask,
            callback: dragEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func begin(button: CompoundTapButton, clickCount: Int64) {
        stateLock.lock()
        activeDrag = ActiveDrag(button: button, clickCount: clickCount)
        stateLock.unlock()
    }

    func buttonEvent(isDown: Bool, at location: CGPoint, button: CompoundTapButton, clickCount: Int64) -> CGEvent? {
        eventFactory.buttonEvent(isDown: isDown, at: location, button: button, clickCount: clickCount)
    }

    var eventPostLocation: CGEventTapLocation {
        DragMotionEventMapper.postLocation
    }

    func end() {
        stateLock.lock()
        activeDrag = nil
        stateLock.unlock()
    }

    func beginPinch() {
        setScrollSuppressionEnabled(true)
    }

    func endPinch() {
        setScrollSuppressionEnabled(false)
    }

    func setScrollSuppressionEnabled(_ enabled: Bool) {
        stateLock.lock()
        suppressesScroll = enabled
        stateLock.unlock()
    }

    func stop() {
        end()
        endPinch()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        let drag = activeDrag
        let shouldSuppressScroll = suppressesScroll
        stateLock.unlock()

        if type == .scrollWheel,
           shouldSuppressScroll || drag != nil {
            return nil
        }

        guard DragMotionEventMapper.accepts(type) else {
            return Unmanaged.passUnretained(event)
        }

        guard let drag else {
            return Unmanaged.passUnretained(event)
        }

        guard let freshEvent = eventFactory.freshDragEvent(
            from: event, button: drag.button, clickCount: drag.clickCount
        ) else { return Unmanaged.passUnretained(event) }
        freshEvent.post(tap: DragMotionEventMapper.postLocation)
        return nil
    }

    deinit {
        stop()
    }
}

private let dragEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<DragEventMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
