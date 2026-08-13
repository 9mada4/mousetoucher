import Foundation
import CoreGraphics
import AppKit

enum RecognizedGesture: Equatable {
    case none
    case leftClick
    case rightClick
    case dragStarted
    case dropped
    case zoomIn
    case zoomOut
    case zoomEnded
}

struct GestureStatusSnapshot: Equatable {
    let touchCount: Int
    let state: CompoundGestureState
    let lastRecognizedGesture: RecognizedGesture
    let cancellationReason: CompoundGestureCancellationReason?
}

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    private let stateLock = NSLock()
    private var compoundTapDetector: CompoundTapDetector
    private var isEnabled = true
    private var lastRecognizedGesture: RecognizedGesture = .none
    private var lastStatusSnapshot: GestureStatusSnapshot?

    fileprivate static var sharedInstance: MultitouchManager?

    var onGestureRecognized: ((CGPoint, CompoundGestureEvent) -> Void)?
    var onStatusChanged: ((GestureStatusSnapshot) -> Void)?

    init(configuration: CompoundGestureConfiguration = .default) {
        compoundTapDetector = CompoundTapDetector(configuration: configuration)
        MultitouchManager.sharedInstance = self
    }

    func start() {
        guard let deviceList = MTDeviceCreateList() else {
            return
        }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        let count = CFArrayGetCount(deviceArray)

        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)

            // Only monitor external devices (Magic Mouse), skip built-in trackpads
            let isBuiltIn = MTDeviceIsBuiltIn(device)

            if !isBuiltIn {
                devices.append(device)
                MTRegisterContactFrameCallback(device, touchCallback)
                MTDeviceStart(device, 0)
            }
        }
    }

    func stop() {
        cancelGesture(reason: .disabled, touchCount: 0)
        for device in devices {
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        isEnabled = enabled
        let event: CompoundGestureEvent?
        if enabled {
            compoundTapDetector.reset()
            event = nil
        } else {
            event = compoundTapDetector.cancel(reason: .disabled)
        }
        if let event {
            lastRecognizedGesture = recognizedGesture(for: event)
        }
        let status = makeStatus(touchCount: 0)
        stateLock.unlock()

        if let event {
            emit(event)
        }
        publish(status)
    }

    func updateConfiguration(_ configuration: CompoundGestureConfiguration) {
        stateLock.lock()
        let event = compoundTapDetector.updateConfiguration(configuration)
        if let event {
            lastRecognizedGesture = recognizedGesture(for: event)
        }
        let status = makeStatus(touchCount: 0)
        stateLock.unlock()

        if let event {
            emit(event)
        }
        publish(status)
    }

    func processTouches(_ touches: [CompoundTouch], timestamp: Double) {
        stateLock.lock()
        let enabled = isEnabled
        let dragIsActive = compoundTapDetector.activeDragButton != nil
        stateLock.unlock()

        guard enabled else {
            cancelGesture(reason: .disabled, touchCount: touches.count)
            return
        }

        let physicalButtonIsPressed =
            CGEventSource.buttonState(.hidSystemState, button: .left) ||
            CGEventSource.buttonState(.hidSystemState, button: .right)

        if physicalButtonIsPressed && !dragIsActive {
            cancelGesture(reason: .physicalButtonPressed, touchCount: touches.count)
            return
        }

        stateLock.lock()
        let event = compoundTapDetector.process(touches: touches, timestamp: timestamp)
        if let event {
            lastRecognizedGesture = recognizedGesture(for: event)
        }
        let status = makeStatus(touchCount: touches.count)
        stateLock.unlock()

        if let event {
            emit(event)
        }
        publish(status)
    }

    private func cancelGesture(reason: CompoundGestureCancellationReason, touchCount: Int) {
        stateLock.lock()
        let event = compoundTapDetector.cancel(reason: reason)
        if let event {
            lastRecognizedGesture = recognizedGesture(for: event)
        }
        let status = makeStatus(touchCount: touchCount)
        stateLock.unlock()

        if let event {
            emit(event)
        }
        publish(status)
    }

    private func emit(_ event: CompoundGestureEvent) {
        let cursorLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
        onGestureRecognized?(cursorLocation, event)
    }

    private func makeStatus(touchCount: Int) -> GestureStatusSnapshot {
        GestureStatusSnapshot(
            touchCount: touchCount,
            state: compoundTapDetector.gestureState,
            lastRecognizedGesture: lastRecognizedGesture,
            cancellationReason: compoundTapDetector.lastCancellationReason
        )
    }

    private func publish(_ status: GestureStatusSnapshot) {
        stateLock.lock()
        guard status != lastStatusSnapshot else {
            stateLock.unlock()
            return
        }
        lastStatusSnapshot = status
        stateLock.unlock()
        onStatusChanged?(status)
    }

    private func recognizedGesture(for event: CompoundGestureEvent) -> RecognizedGesture {
        switch event {
        case .click(let tap):
            return tap.button == .left ? .leftClick : .rightClick
        case .dragBegan:
            return .dragStarted
        case .dragEnded:
            return .dropped
        case .magnify(let magnification):
            if magnification.phase == .ended {
                return .zoomEnded
            }
            return magnification.amount >= 0 ? .zoomIn : .zoomOut
        }
    }

    deinit {
        stop()
    }
}

private func touchCallback(device: Int32, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
    guard let manager = MultitouchManager.sharedInstance else { return 0 }

    var activeTouches: [CompoundTouch] = []
    if let touches, numTouches > 0 {
        for index in 0..<Int(numTouches) {
            let touch = touches[index]

            // MakeTouch and Touching are real surface contact. Hover, break,
            // linger, and out-of-range frames must not become anchors.
            guard touch.state == 3 || touch.state == 4 else { continue }

            activeTouches.append(
                CompoundTouch(
                    identifier: touch.identifier,
                    position: CGPoint(
                        x: CGFloat(touch.normalized.position.x),
                        y: CGFloat(touch.normalized.position.y)
                    )
                )
            )
        }
    }

    manager.processTouches(activeTouches, timestamp: timestamp)
    return 0
}
