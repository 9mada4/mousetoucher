import CoreGraphics
import Foundation

enum CompoundTapButton: Equatable {
    case left
    case right
}

struct CompoundGestureConfiguration: Equatable {
    static let defaultTapTimeThreshold: TimeInterval = 0.28
    static let defaultMovementThreshold: CGFloat = 0.04
    static let defaultRightClickSplit: CGFloat = 0.5
    static let defaultPinchStartThreshold: CGFloat = 0.025
    static let defaultPinchSensitivity: CGFloat = 1.0

    static let `default` = CompoundGestureConfiguration(
        tapTimeThreshold: defaultTapTimeThreshold,
        movementThreshold: defaultMovementThreshold,
        rightClickSplit: defaultRightClickSplit,
        isThreeFingerDragEnabled: true,
        isPinchZoomEnabled: true,
        pinchStartThreshold: defaultPinchStartThreshold,
        pinchSensitivity: defaultPinchSensitivity
    )

    var tapTimeThreshold: TimeInterval
    var movementThreshold: CGFloat
    var rightClickSplit: CGFloat
    var isThreeFingerDragEnabled: Bool
    var isPinchZoomEnabled: Bool
    var pinchStartThreshold: CGFloat
    var pinchSensitivity: CGFloat

    var normalized: CompoundGestureConfiguration {
        CompoundGestureConfiguration(
            tapTimeThreshold: min(max(tapTimeThreshold, 0.10), 0.50),
            movementThreshold: min(max(movementThreshold, 0.01), 0.12),
            rightClickSplit: min(max(rightClickSplit, 0.35), 0.75),
            isThreeFingerDragEnabled: isThreeFingerDragEnabled,
            isPinchZoomEnabled: isPinchZoomEnabled,
            pinchStartThreshold: min(max(pinchStartThreshold, 0.01), 0.08),
            pinchSensitivity: min(max(pinchSensitivity, 0.25), 3.0)
        )
    }
}

enum CompoundGestureState: Equatable {
    case idle
    case anchorReady
    case tapping
    case pinching
    case dragging
    case waitingForRelease
}

enum CompoundGestureCancellationReason: Equatable {
    case anchorReleased
    case anchorMoved
    case tapMoved
    case tapTooLong
    case replacementTouch
    case tooManyFingers
    case threeFingerDragDisabled
    case physicalButtonPressed
    case disabled
    case settingsChanged
}

struct CompoundTouch: Equatable {
    let identifier: Int32
    let position: CGPoint
}

struct CompoundTap: Equatable {
    let button: CompoundTapButton
    let surfaceLocation: CGPoint
}

enum CompoundGestureEvent: Equatable {
    case click(CompoundTap)
    case dragBegan(CompoundTap)
    case dragEnded(CompoundTapButton)
    case magnify(CompoundMagnification)
}

enum CompoundMagnificationPhase: Equatable {
    case began
    case changed
    case ended
}

struct CompoundMagnification: Equatable {
    let phase: CompoundMagnificationPhase
    let amount: CGFloat
}

/// Recognizes a tap made while another finger remains on the surface, a
/// continuous two-finger pinch, and an immediate three-finger drag.
///
/// The first finger becomes the anchor. A second finger must touch and release
/// without either finger moving beyond the configured threshold. The anchor
/// remains active after a successful gesture so it can be reused for
/// consecutive clicks. Moving two fingers apart or together emits incremental
/// magnification values. Three simultaneous touches begin a left-button drag
/// immediately; the drag ends only after every finger lifts.
final class CompoundTapDetector {
    private(set) var configuration: CompoundGestureConfiguration

    private struct TrackedTouch {
        let identifier: Int32
        let startPosition: CGPoint
        let startTime: TimeInterval
    }

    private var anchor: TrackedTouch?
    private var tappingFinger: TrackedTouch?
    private var tappingFingerWasRejected = false
    private var tapIsEligible = true
    private var pinchInitialDistance: CGFloat?
    private var pinchPreviousDistance: CGFloat?
    private(set) var isPinching = false
    private var canBeginTap = true
    private var requiresAllFingersReleased = false
    private(set) var activeDragButton: CompoundTapButton?
    private(set) var lastCancellationReason: CompoundGestureCancellationReason?

    var gestureState: CompoundGestureState {
        if activeDragButton != nil {
            return .dragging
        }
        if isPinching {
            return .pinching
        }
        if requiresAllFingersReleased {
            return .waitingForRelease
        }
        if tappingFinger != nil {
            return .tapping
        }
        if anchor != nil {
            return .anchorReady
        }
        return .idle
    }

    var tapTimeThreshold: TimeInterval { configuration.tapTimeThreshold }
    var movementThreshold: CGFloat { configuration.movementThreshold }
    var rightClickSplit: CGFloat { configuration.rightClickSplit }

    init(
        tapTimeThreshold: TimeInterval = 0.28,
        movementThreshold: CGFloat = 0.04,
        rightClickSplit: CGFloat = 0.5,
        isThreeFingerDragEnabled: Bool = true,
        isPinchZoomEnabled: Bool = true,
        pinchStartThreshold: CGFloat = 0.025,
        pinchSensitivity: CGFloat = 1.0
    ) {
        configuration = CompoundGestureConfiguration(
            tapTimeThreshold: tapTimeThreshold,
            movementThreshold: movementThreshold,
            rightClickSplit: rightClickSplit,
            isThreeFingerDragEnabled: isThreeFingerDragEnabled,
            isPinchZoomEnabled: isPinchZoomEnabled,
            pinchStartThreshold: pinchStartThreshold,
            pinchSensitivity: pinchSensitivity
        ).normalized
    }

    init(configuration: CompoundGestureConfiguration) {
        self.configuration = configuration.normalized
    }

    func process(touches: [CompoundTouch], timestamp: TimeInterval) -> CompoundGestureEvent? {
        if touches.isEmpty {
            let endingEvent = endingContinuousGestureEvent()
            resetTracking()
            if endingEvent != nil {
                lastCancellationReason = nil
            }
            return endingEvent
        }

        // Once a three-finger drag starts, tolerate finger movement and partial
        // contact loss. Releasing every finger is the explicit drop gesture.
        if activeDragButton != nil {
            return nil
        }

        if touches.count >= 3 {
            // Switching directly from pinch to drag would require an end and a
            // begin event in the same frame. End the pinch cleanly and require
            // a fresh contact sequence instead.
            if isPinching {
                return invalidateUntilAllFingersAreReleased(reason: .tooManyFingers)
            }

            guard configuration.isThreeFingerDragEnabled else {
                return invalidateUntilAllFingersAreReleased(reason: .threeFingerDragDisabled)
            }

            let surfaceLocation = touches.reduce(CGPoint.zero) { partial, touch in
                CGPoint(
                    x: partial.x + touch.position.x / CGFloat(touches.count),
                    y: partial.y + touch.position.y / CGFloat(touches.count)
                )
            }
            anchor = nil
            tappingFinger = nil
            tappingFingerWasRejected = false
            tapIsEligible = false
            resetPinchTracking()
            canBeginTap = false
            requiresAllFingersReleased = false
            activeDragButton = .left
            lastCancellationReason = nil
            return .dragBegan(CompoundTap(button: .left, surfaceLocation: surfaceLocation))
        }

        guard !requiresAllFingersReleased else { return nil }

        guard let anchor else {
            if touches.count == 1, let firstTouch = touches.first {
                self.anchor = TrackedTouch(
                    identifier: firstTouch.identifier,
                    startPosition: firstTouch.position,
                    startTime: timestamp
                )
                return nil
            }

            // Two fingers may land in the same hardware frame. Treat this as
            // a pinch-only candidate so the gesture still feels trackpad-like,
            // but never reinterpret its release as a click.
            if touches.count == 2, configuration.isPinchZoomEnabled {
                let orderedTouches = touches.sorted { $0.identifier < $1.identifier }
                let firstTouch = orderedTouches[0]
                let secondTouch = orderedTouches[1]
                self.anchor = TrackedTouch(
                    identifier: firstTouch.identifier,
                    startPosition: firstTouch.position,
                    startTime: timestamp
                )
                beginSecondaryTracking(
                    secondaryTouch: secondTouch,
                    currentAnchor: firstTouch,
                    timestamp: timestamp,
                    tapEligible: false
                )
                return nil
            }

            guard touches.count == 1 else {
                return invalidateUntilAllFingersAreReleased(reason: .tooManyFingers)
            }
            return nil
        }

        guard let currentAnchor = touches.first(where: { $0.identifier == anchor.identifier }) else {
            // Do not reinterpret the tapping finger as an anchor mid-gesture.
            return invalidateUntilAllFingersAreReleased(
                reason: tappingFinger == nil ? nil : .anchorReleased
            )
        }

        let secondaryTouches = touches.filter { $0.identifier != anchor.identifier }
        guard secondaryTouches.count <= 1 else {
            return invalidateUntilAllFingersAreReleased(reason: .tooManyFingers)
        }

        guard let tappingFinger else {
            if secondaryTouches.isEmpty {
                canBeginTap = true
                rebaseAnchor(to: currentAnchor, timestamp: timestamp)
            } else if canBeginTap, let secondaryTouch = secondaryTouches.first {
                beginSecondaryTracking(
                    secondaryTouch: secondaryTouch,
                    currentAnchor: currentAnchor,
                    timestamp: timestamp,
                    tapEligible: true
                )
            }
            return nil
        }

        if let currentTap = secondaryTouches.first(where: { $0.identifier == tappingFinger.identifier }) {
            let currentDistance = distance(from: currentAnchor.position, to: currentTap.position)
            let initialDistance = pinchInitialDistance ?? currentDistance

            if isPinching {
                let previousDistance = pinchPreviousDistance ?? currentDistance
                pinchPreviousDistance = currentDistance
                let amount = magnificationAmount(
                    distanceDelta: currentDistance - previousDistance,
                    initialDistance: initialDistance
                )
                guard abs(amount) > 0.000_01 else { return nil }
                return .magnify(CompoundMagnification(phase: .changed, amount: amount))
            }

            if configuration.isPinchZoomEnabled,
               abs(currentDistance - initialDistance) >= configuration.pinchStartThreshold {
                isPinching = true
                tapIsEligible = false
                tappingFingerWasRejected = false
                pinchPreviousDistance = currentDistance
                lastCancellationReason = nil
                return .magnify(
                    CompoundMagnification(
                        phase: .began,
                        amount: magnificationAmount(
                            distanceDelta: currentDistance - initialDistance,
                            initialDistance: initialDistance
                        )
                    )
                )
            }

            let duration = timestamp - tappingFinger.startTime
            if duration < 0 || duration > tapTimeThreshold {
                tappingFingerWasRejected = true
                lastCancellationReason = .tapTooLong
            } else if distance(from: anchor.startPosition, to: currentAnchor.position) > movementThreshold {
                tappingFingerWasRejected = true
                lastCancellationReason = .anchorMoved
            } else if distance(from: tappingFinger.startPosition, to: currentTap.position) > movementThreshold {
                tappingFingerWasRejected = true
                lastCancellationReason = .tapMoved
            }
            return nil
        }

        // Accept another tap only after a clean anchor-only frame. This prevents
        // a replacement touch identifier from being interpreted as a release.
        guard secondaryTouches.isEmpty else {
            return invalidateUntilAllFingersAreReleased(reason: .replacementTouch)
        }

        rebaseAnchor(to: currentAnchor, timestamp: timestamp)

        if isPinching {
            clearSecondaryTracking(canBeginNextTap: true)
            lastCancellationReason = nil
            return .magnify(CompoundMagnification(phase: .ended, amount: 0))
        }

        if distance(from: anchor.startPosition, to: currentAnchor.position) > movementThreshold {
            tappingFingerWasRejected = true
            lastCancellationReason = .anchorMoved
        }

        defer {
            clearSecondaryTracking(canBeginNextTap: true)
        }

        let duration = timestamp - tappingFinger.startTime
        guard tapIsEligible,
              !tappingFingerWasRejected,
              duration >= 0,
              duration <= tapTimeThreshold else {
            if tapIsEligible, lastCancellationReason == nil {
                lastCancellationReason = .tapTooLong
            }
            return nil
        }

        lastCancellationReason = nil
        return .click(makeTap(from: tappingFinger))
    }

    /// Cancels recognition and returns a matching end event for a continuous gesture.
    func cancel(reason: CompoundGestureCancellationReason = .disabled) -> CompoundGestureEvent? {
        let endingEvent = endingContinuousGestureEvent()
        resetTracking()
        lastCancellationReason = reason
        return endingEvent
    }

    func updateConfiguration(_ configuration: CompoundGestureConfiguration) -> CompoundGestureEvent? {
        let normalized = configuration.normalized
        guard normalized != self.configuration else { return nil }

        self.configuration = normalized
        return cancel(reason: .settingsChanged)
    }

    func reset() {
        resetTracking()
        lastCancellationReason = nil
    }

    private func resetTracking() {
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        tapIsEligible = true
        resetPinchTracking()
        canBeginTap = true
        requiresAllFingersReleased = false
        activeDragButton = nil
    }

    private func invalidateUntilAllFingersAreReleased(
        reason: CompoundGestureCancellationReason?
    ) -> CompoundGestureEvent? {
        let endingEvent = endingContinuousGestureEvent()
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        tapIsEligible = true
        resetPinchTracking()
        canBeginTap = false
        requiresAllFingersReleased = true
        activeDragButton = nil
        if let reason {
            lastCancellationReason = reason
        }
        return endingEvent
    }

    private func beginSecondaryTracking(
        secondaryTouch: CompoundTouch,
        currentAnchor: CompoundTouch,
        timestamp: TimeInterval,
        tapEligible: Bool
    ) {
        tappingFinger = TrackedTouch(
            identifier: secondaryTouch.identifier,
            startPosition: secondaryTouch.position,
            startTime: timestamp
        )
        tappingFingerWasRejected = false
        tapIsEligible = tapEligible
        let initialDistance = distance(from: currentAnchor.position, to: secondaryTouch.position)
        pinchInitialDistance = initialDistance
        pinchPreviousDistance = initialDistance
        isPinching = false
        canBeginTap = false
    }

    private func clearSecondaryTracking(canBeginNextTap: Bool) {
        tappingFinger = nil
        tappingFingerWasRejected = false
        tapIsEligible = true
        resetPinchTracking()
        canBeginTap = canBeginNextTap
    }

    private func resetPinchTracking() {
        pinchInitialDistance = nil
        pinchPreviousDistance = nil
        isPinching = false
    }

    private func endingContinuousGestureEvent() -> CompoundGestureEvent? {
        if let activeDragButton {
            return .dragEnded(activeDragButton)
        }
        if isPinching {
            return .magnify(CompoundMagnification(phase: .ended, amount: 0))
        }
        return nil
    }

    private func magnificationAmount(
        distanceDelta: CGFloat,
        initialDistance: CGFloat
    ) -> CGFloat {
        let safeInitialDistance = max(initialDistance, 0.05)
        let unbounded = distanceDelta / safeInitialDistance * configuration.pinchSensitivity
        return min(max(unbounded, -0.08), 0.08)
    }

    private func makeTap(from touch: TrackedTouch) -> CompoundTap {
        let button: CompoundTapButton = touch.startPosition.x >= rightClickSplit ? .right : .left
        return CompoundTap(button: button, surfaceLocation: touch.startPosition)
    }

    private func rebaseAnchor(to touch: CompoundTouch, timestamp: TimeInterval) {
        anchor = TrackedTouch(
            identifier: touch.identifier,
            startPosition: touch.position,
            startTime: timestamp
        )
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

/// Produces the click-state values macOS expects for double- and multi-clicks.
struct ClickSequenceTracker {
    let doubleClickInterval: TimeInterval
    let maximumCursorMovement: CGFloat

    private var lastButton: CompoundTapButton?
    private var lastTimestamp: TimeInterval?
    private var lastLocation: CGPoint?
    private var clickCount = 0

    init(doubleClickInterval: TimeInterval, maximumCursorMovement: CGFloat = 5.0) {
        self.doubleClickInterval = doubleClickInterval
        self.maximumCursorMovement = maximumCursorMovement
    }

    mutating func nextClickCount(
        button: CompoundTapButton,
        location: CGPoint,
        timestamp: TimeInterval
    ) -> Int64 {
        let continuesSequence: Bool

        if let lastButton,
           let lastTimestamp,
           let lastLocation {
            let elapsed = timestamp - lastTimestamp
            continuesSequence = lastButton == button &&
                elapsed >= 0 &&
                elapsed <= doubleClickInterval &&
                hypot(location.x - lastLocation.x, location.y - lastLocation.y) <= maximumCursorMovement
        } else {
            continuesSequence = false
        }

        clickCount = continuesSequence ? clickCount + 1 : 1
        lastButton = button
        lastTimestamp = timestamp
        lastLocation = location

        return Int64(clickCount)
    }

    mutating func reset() {
        lastButton = nil
        lastTimestamp = nil
        lastLocation = nil
        clickCount = 0
    }
}
