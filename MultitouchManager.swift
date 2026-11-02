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

struct MultitouchDeviceSnapshot {
    let devices: [MTDeviceRef]
    let retainedList: NSArray?
}

/// The framework boundary can be replaced in tests without opening devices.
struct MultitouchDeviceAccess {
    var snapshot: () -> MultitouchDeviceSnapshot?
    var start: (MTDeviceRef) -> Void
    var stop: (MTDeviceRef) -> Void

    static let system = MultitouchDeviceAccess(
        snapshot: {
            guard let list = MTDeviceCreateList() else { return nil }
            let array = list.takeRetainedValue() as NSArray
            var devices: [MTDeviceRef] = []
            for index in 0..<CFArrayGetCount(array) {
                let device = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: MTDeviceRef.self)
                if !MTDeviceIsBuiltIn(device) { devices.append(device) }
            }
            return MultitouchDeviceSnapshot(devices: devices, retainedList: array)
        },
        start: {
            MTRegisterContactFrameCallback($0, touchCallback)
            MTDeviceStart($0, 0)
        },
        stop: {
            MTUnregisterContactFrameCallback($0, touchCallback)
            MTDeviceStop($0)
        }
    )
}

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    // Retain the framework's array while using its device references.
    private var deviceList: NSArray?
    private let stateLock = NSLock()
    private let deviceAccess: MultitouchDeviceAccess
    private let physicalButtonIsPressed: () -> Bool
    private var isRefreshingDevices = false
    private var compoundTapDetector: CompoundTapDetector
    private var isEnabled = true
    private var lastRecognizedGesture: RecognizedGesture = .none
    private var lastStatusSnapshot: GestureStatusSnapshot?

    fileprivate static var sharedInstance: MultitouchManager?

    var onGestureRecognized: ((CGPoint, CompoundGestureEvent) -> Void)?
    var onStatusChanged: ((GestureStatusSnapshot) -> Void)?

    init(
        configuration: CompoundGestureConfiguration = .default,
        deviceAccess: MultitouchDeviceAccess = .system,
        physicalButtonIsPressed: @escaping () -> Bool = {
            CGEventSource.buttonState(.hidSystemState, button: .left) ||
            CGEventSource.buttonState(.hidSystemState, button: .right)
        }
    ) {
        compoundTapDetector = CompoundTapDetector(configuration: configuration)
        self.deviceAccess = deviceAccess
        self.physicalButtonIsPressed = physicalButtonIsPressed
        MultitouchManager.sharedInstance = self
    }

    func start() {
        refreshDevices(force: true)
    }

    /// Periodic reconnect checks wait until a latched drag has ended. Forced
    /// refresh is reserved for startup and wake, after explicit cancellation.
    func refreshDevices(force: Bool = false) {
        stateLock.lock()
        let dragIsActive = compoundTapDetector.activeDragButton != nil
        stateLock.unlock()
        guard force || !dragIsActive else { return }

        guard let snapshot = deviceAccess.snapshot() else {
            guard beginDeviceRefresh(force: force) else { return }
            defer { finishDeviceRefresh() }
            if !devices.isEmpty { stop() }
            return
        }

        let currentIDs = Set(devices.map { UInt(bitPattern: $0) })
        let availableIDs = Set(snapshot.devices.map { UInt(bitPattern: $0) })
        guard force || currentIDs != availableIDs else { return }
        // A callback may have begun a drag while enumeration was in progress.
        guard beginDeviceRefresh(force: force) else { return }
        defer { finishDeviceRefresh() }

        stop()
        deviceList = snapshot.retainedList
        devices = snapshot.devices
        for device in devices { deviceAccess.start(device) }
    }

    private func beginDeviceRefresh(force: Bool) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRefreshingDevices,
              force || compoundTapDetector.activeDragButton == nil else { return false }
        isRefreshingDevices = true
        return true
    }

    private func finishDeviceRefresh() {
        stateLock.lock()
        isRefreshingDevices = false
        stateLock.unlock()
    }

    func stop() {
        cancelGesture(reason: .disabled, touchCount: 0)
        for device in devices { deviceAccess.stop(device) }
        devices.removeAll()
        deviceList = nil
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
        guard !isRefreshingDevices else {
            stateLock.unlock()
            return
        }
        let enabled = isEnabled
        let dragIsActive = compoundTapDetector.activeDragButton != nil
        stateLock.unlock()

        guard enabled else {
            cancelGesture(reason: .disabled, touchCount: touches.count)
            return
        }

        if physicalButtonIsPressed() && !dragIsActive {
            cancelGesture(reason: .physicalButtonPressed, touchCount: touches.count)
            return
        }

        stateLock.lock()
        // Keep callback processing and the refresh gate atomic. Framework
        // stop/start calls stay outside the lock because they can invoke callbacks.
        guard !isRefreshingDevices else {
            stateLock.unlock()
            return
        }
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
