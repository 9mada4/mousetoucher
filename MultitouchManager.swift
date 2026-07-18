import Foundation
import CoreGraphics
import AppKit

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    private var compoundTapDetector = CompoundTapDetector(
        tapTimeThreshold: 0.28,
        movementThreshold: 0.04,
        rightClickSplit: 0.5
    )
    private var isEnabled = true

    fileprivate static var sharedInstance: MultitouchManager?

    var onClickSynthesized: ((CGPoint, CompoundTapButton) -> Void)?

    init() {
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
        for device in devices {
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            compoundTapDetector.reset()
        }
    }

    func processTouches(_ touches: [CompoundTouch], timestamp: Double) {
        guard isEnabled else {
            compoundTapDetector.reset()
            return
        }

        let physicalButtonIsPressed =
            CGEventSource.buttonState(.hidSystemState, button: .left) ||
            CGEventSource.buttonState(.hidSystemState, button: .right)

        if physicalButtonIsPressed {
            compoundTapDetector.reset()
            return
        }

        if let tap = compoundTapDetector.process(touches: touches, timestamp: timestamp) {
            let cursorLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
            onClickSynthesized?(cursorLocation, tap.button)
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
