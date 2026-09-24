import CoreGraphics
import Foundation

enum DragMotionEventMapper {
    static func tapLocation(for mode: DragCompatibilityMode) -> CGEventTapLocation {
        mode.resolved() == .macOS27 ? .cghidEventTap : .cgSessionEventTap
    }

    static func accepts(_ type: CGEventType, mode: DragCompatibilityMode) -> Bool {
        if type == .mouseMoved { return true }
        return mode.resolved() == .macOS27 &&
            (type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged)
    }

    static func eventMask(for mode: DragCompatibilityMode) -> CGEventMask {
        let motionTypes: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        return motionTypes.filter { accepts($0, mode: mode) }.reduce(
            CGEventMask(1) << CGEventType.scrollWheel.rawValue
        ) { $0 | (CGEventMask(1) << $1.rawValue) }
    }

    static func eventType(for button: CompoundTapButton) -> CGEventType {
        button == .right ? .rightMouseDragged : .leftMouseDragged
    }

    static func buttonNumber(for button: CompoundTapButton) -> Int64 {
        Int64(button == .right ? CGMouseButton.right.rawValue : CGMouseButton.left.rawValue)
    }
}

/// A single source pairs the down/move/up events of a modern drag. Explicitly
/// allow hardware input during a synthetic drag; otherwise Quartz can suppress
/// the very mouse movement that must be converted into dragged events.
final class DragMouseEventFactory {
    let source: CGEventSource?
    let mode: DragCompatibilityMode

    init(mode: DragCompatibilityMode) {
        self.mode = mode.resolved()
        source = self.mode == .macOS27 ? CGEventSource(stateID: .privateState) : nil
        if let source {
            source.localEventsSuppressionInterval = 0
            let allowedEvents: CGEventFilterMask = [
                .permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents
            ]
            source.setLocalEventsFilterDuringSuppressionState(allowedEvents, state: .eventSuppressionStateSuppressionInterval)
            source.setLocalEventsFilterDuringSuppressionState(allowedEvents, state: .eventSuppressionStateRemoteMouseDrag)
        }
    }

    var isAvailable: Bool { mode == .macOS26 || source != nil }

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
        if mode == .macOS27 {
            event.flags = CGEventSource.flagsState(.combinedSessionState)
        }
        return event
    }

    func convertMotion(_ event: CGEvent, button: CompoundTapButton, clickCount: Int64) {
        if let source {
            event.setSource(source)
        }
        event.type = DragMotionEventMapper.eventType(for: button)
        event.setIntegerValueField(.mouseEventButtonNumber, value: DragMotionEventMapper.buttonNumber(for: button))
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
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
    private var isWindowDragging = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var compatibilityMode: DragCompatibilityMode = .macOS26
    private var eventFactory = DragMouseEventFactory(mode: .macOS26)

    @discardableResult
    func start(mode: DragCompatibilityMode = .automatic) -> Bool {
        let resolvedMode = mode.resolved()
        if resolvedMode != compatibilityMode {
            stop()
            compatibilityMode = resolvedMode
            eventFactory = DragMouseEventFactory(mode: resolvedMode)
        }
        guard eventTap == nil else { return true }
        guard eventFactory.isAvailable else { return false }

        guard let eventTap = CGEvent.tapCreate(
            tap: DragMotionEventMapper.tapLocation(for: resolvedMode),
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: DragMotionEventMapper.eventMask(for: resolvedMode),
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

    func end() {
        stateLock.lock()
        activeDrag = nil
        isWindowDragging = false
        stateLock.unlock()
    }

    func beginWindowDrag() {
        stateLock.lock()
        isWindowDragging = true
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
        let windowDrag = isWindowDragging
        stateLock.unlock()

        if type == .scrollWheel,
           shouldSuppressScroll || windowDrag || (drag != nil && compatibilityMode == .macOS27) {
            return nil
        }

        guard DragMotionEventMapper.accepts(type, mode: compatibilityMode) else {
            return Unmanaged.passUnretained(event)
        }

        guard let drag else {
            return Unmanaged.passUnretained(event)
        }

        eventFactory.convertMotion(event, button: drag.button, clickCount: drag.clickCount)
        return Unmanaged.passUnretained(event)
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
