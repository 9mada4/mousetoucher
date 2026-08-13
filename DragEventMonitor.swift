import CoreGraphics
import Foundation

enum DragMotionEventMapper {
    static func eventType(for button: CompoundTapButton) -> CGEventType {
        button == .right ? .rightMouseDragged : .leftMouseDragged
    }

    static func buttonNumber(for button: CompoundTapButton) -> Int64 {
        Int64(button == .right ? CGMouseButton.right.rawValue : CGMouseButton.left.rawValue)
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

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask =
            (CGEventMask(1) << CGEventType.mouseMoved.rawValue) |
            (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
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

        if type == .scrollWheel, shouldSuppressScroll {
            return nil
        }

        guard type == .mouseMoved else {
            return Unmanaged.passUnretained(event)
        }

        guard let drag else {
            return Unmanaged.passUnretained(event)
        }

        event.type = DragMotionEventMapper.eventType(for: drag.button)
        event.setIntegerValueField(.mouseEventButtonNumber, value: DragMotionEventMapper.buttonNumber(for: drag.button))
        event.setIntegerValueField(.mouseEventClickState, value: drag.clickCount)
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
