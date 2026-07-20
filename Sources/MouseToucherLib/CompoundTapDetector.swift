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

    static let `default` = CompoundGestureConfiguration(
        tapTimeThreshold: defaultTapTimeThreshold,
        movementThreshold: defaultMovementThreshold,
        rightClickSplit: defaultRightClickSplit,
        isThreeFingerDragEnabled: true
    )

    var tapTimeThreshold: TimeInterval
    var movementThreshold: CGFloat
    var rightClickSplit: CGFloat
    var isThreeFingerDragEnabled: Bool

    var normalized: CompoundGestureConfiguration {
        CompoundGestureConfiguration(
            tapTimeThreshold: min(max(tapTimeThreshold, 0.10), 0.50),
            movementThreshold: min(max(movementThreshold, 0.01), 0.12),
            rightClickSplit: min(max(rightClickSplit, 0.35), 0.75),
            isThreeFingerDragEnabled: isThreeFingerDragEnabled
        )
    }
}

enum CompoundGestureState: Equatable {
    case idle
    case anchorReady
    case tapping
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
}

/// Recognizes a tap made while another finger remains on the surface, plus an
/// immediate three-finger drag.
///
/// The first finger becomes the anchor. A second finger must touch and release
/// without either finger moving beyond the configured threshold. The anchor
/// remains active after a successful gesture so it can be reused for
/// consecutive clicks. Three simultaneous touches begin a left-button drag
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
    private var canBeginTap = true
    private var requiresAllFingersReleased = false
    private(set) var activeDragButton: CompoundTapButton?
    private(set) var lastCancellationReason: CompoundGestureCancellationReason?

    var gestureState: CompoundGestureState {
        if activeDragButton != nil {
            return .dragging
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
        isThreeFingerDragEnabled: Bool = true
    ) {
        configuration = CompoundGestureConfiguration(
            tapTimeThreshold: tapTimeThreshold,
            movementThreshold: movementThreshold,
            rightClickSplit: rightClickSplit,
            isThreeFingerDragEnabled: isThreeFingerDragEnabled
        ).normalized
    }

    init(configuration: CompoundGestureConfiguration) {
        self.configuration = configuration.normalized
    }

    func process(touches: [CompoundTouch], timestamp: TimeInterval) -> CompoundGestureEvent? {
        if touches.isEmpty {
            let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
            resetTracking()
            if dragEnd != nil {
                lastCancellationReason = nil
            }
            return dragEnd
        }

        // Once a three-finger drag starts, tolerate finger movement and partial
        // contact loss. Releasing every finger is the explicit drop gesture.
        if activeDragButton != nil {
            return nil
        }

        if touches.count >= 3 {
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
            canBeginTap = false
            requiresAllFingersReleased = false
            activeDragButton = .left
            lastCancellationReason = nil
            return .dragBegan(CompoundTap(button: .left, surfaceLocation: surfaceLocation))
        }

        guard !requiresAllFingersReleased else { return nil }

        guard let anchor else {
            guard touches.count == 1, let firstTouch = touches.first else {
                return invalidateUntilAllFingersAreReleased(reason: .tooManyFingers)
            }

            self.anchor = TrackedTouch(
                identifier: firstTouch.identifier,
                startPosition: firstTouch.position,
                startTime: timestamp
            )
            return nil
        }

        guard let currentAnchor = touches.first(where: { $0.identifier == anchor.identifier }) else {
            // Do not reinterpret the tapping finger as an anchor mid-gesture.
            return invalidateUntilAllFingersAreReleased(
                reason: tappingFinger == nil ? nil : .anchorReleased
            )
        }

        let anchorMovedTooFar = distance(
            from: anchor.startPosition,
            to: currentAnchor.position
        ) > movementThreshold

        if anchorMovedTooFar {
            if tappingFinger == nil {
                rebaseAnchor(to: currentAnchor, timestamp: timestamp)
            } else {
                tappingFingerWasRejected = true
                lastCancellationReason = .anchorMoved
            }
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
                self.tappingFinger = TrackedTouch(
                    identifier: secondaryTouch.identifier,
                    startPosition: secondaryTouch.position,
                    startTime: timestamp
                )
                tappingFingerWasRejected = false
                canBeginTap = false
            }
            return nil
        }

        if let currentTap = secondaryTouches.first(where: { $0.identifier == tappingFinger.identifier }) {
            let duration = timestamp - tappingFinger.startTime
            if duration < 0 || duration > tapTimeThreshold {
                tappingFingerWasRejected = true
                lastCancellationReason = .tapTooLong
            } else if distance(from: tappingFinger.startPosition, to: currentTap.position) > movementThreshold {
                tappingFingerWasRejected = true
                lastCancellationReason = .tapMoved
            }
            return nil
        }

        // Accept another tap only after a clean anchor-only frame. This prevents
        // a replacement touch identifier from being interpreted as a release.
        guard secondaryTouches.isEmpty else {
            self.tappingFinger = nil
            tappingFingerWasRejected = false
            canBeginTap = false
            lastCancellationReason = .replacementTouch
            return nil
        }

        rebaseAnchor(to: currentAnchor, timestamp: timestamp)

        defer {
            self.tappingFinger = nil
            tappingFingerWasRejected = false
            canBeginTap = true
        }

        let duration = timestamp - tappingFinger.startTime
        guard !tappingFingerWasRejected,
              duration >= 0,
              duration <= tapTimeThreshold else {
            if lastCancellationReason == nil {
                lastCancellationReason = .tapTooLong
            }
            return nil
        }

        lastCancellationReason = nil
        return .click(makeTap(from: tappingFinger))
    }

    /// Cancels recognition and returns a matching mouse-up event if a drag is active.
    func cancel(reason: CompoundGestureCancellationReason = .disabled) -> CompoundGestureEvent? {
        let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
        resetTracking()
        lastCancellationReason = reason
        return dragEnd
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
        canBeginTap = true
        requiresAllFingersReleased = false
        activeDragButton = nil
    }

    private func invalidateUntilAllFingersAreReleased(
        reason: CompoundGestureCancellationReason?
    ) -> CompoundGestureEvent? {
        let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        canBeginTap = false
        requiresAllFingersReleased = true
        activeDragButton = nil
        if let reason {
            lastCancellationReason = reason
        }
        return dragEnd
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
