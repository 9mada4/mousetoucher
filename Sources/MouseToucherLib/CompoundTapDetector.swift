import CoreGraphics
import Foundation

enum CompoundTapButton: Equatable {
    case left
    case right
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

/// Recognizes a tap or tap-and-hold made while another finger remains stationary.
///
/// The first finger becomes the anchor. A second finger must touch and release
/// without either finger moving beyond the configured threshold. The anchor
/// remains active after a successful gesture so it can be reused for
/// consecutive clicks. Holding the second finger beyond `tapTimeThreshold`
/// begins a drag that ends when the second finger lifts.
final class CompoundTapDetector {
    let tapTimeThreshold: TimeInterval
    let movementThreshold: CGFloat
    let rightClickSplit: CGFloat

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

    init(
        tapTimeThreshold: TimeInterval = 0.28,
        movementThreshold: CGFloat = 0.04,
        rightClickSplit: CGFloat = 0.5
    ) {
        self.tapTimeThreshold = tapTimeThreshold
        self.movementThreshold = movementThreshold
        self.rightClickSplit = rightClickSplit
    }

    func process(touches: [CompoundTouch], timestamp: TimeInterval) -> CompoundGestureEvent? {
        if touches.isEmpty {
            let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
            reset()
            return dragEnd
        }

        // Once a drag starts, surface movement is expected: the user is moving
        // the whole mouse while keeping the second finger down. Do not apply
        // the strict tap-movement threshold or require the anchor to remain
        // perfectly stationary. The held second finger alone owns the drag.
        if activeDragButton != nil {
            return processActiveDrag(touches: touches, timestamp: timestamp)
        }

        guard !requiresAllFingersReleased else { return nil }

        guard let anchor else {
            guard touches.count == 1, let firstTouch = touches.first else {
                return invalidateUntilAllFingersAreReleased()
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
            return invalidateUntilAllFingersAreReleased()
        }

        guard distance(from: anchor.startPosition, to: currentAnchor.position) <= movementThreshold else {
            return invalidateUntilAllFingersAreReleased()
        }

        let secondaryTouches = touches.filter { $0.identifier != anchor.identifier }
        guard secondaryTouches.count <= 1 else {
            return invalidateUntilAllFingersAreReleased()
        }

        guard let tappingFinger else {
            if secondaryTouches.isEmpty {
                canBeginTap = true
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
            if duration < 0 || distance(from: tappingFinger.startPosition, to: currentTap.position) > movementThreshold {
                tappingFingerWasRejected = true
                return nil
            }

            if !tappingFingerWasRejected,
               activeDragButton == nil,
               duration >= tapTimeThreshold {
                let tap = makeTap(from: tappingFinger)
                activeDragButton = tap.button
                return .dragBegan(tap)
            }
            return nil
        }

        // Accept another tap only after a clean anchor-only frame. This prevents
        // a replacement touch identifier from being interpreted as a release.
        guard secondaryTouches.isEmpty else {
            let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
            activeDragButton = nil
            self.tappingFinger = nil
            tappingFingerWasRejected = false
            canBeginTap = false
            return dragEnd
        }

        defer {
            self.tappingFinger = nil
            tappingFingerWasRejected = false
            canBeginTap = true
        }

        let duration = timestamp - tappingFinger.startTime
        guard !tappingFingerWasRejected,
              duration >= 0,
              duration <= tapTimeThreshold else {
            return nil
        }

        return .click(makeTap(from: tappingFinger))
    }

    /// Cancels recognition and returns a matching mouse-up event if a drag is active.
    func cancel() -> CompoundGestureEvent? {
        let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
        reset()
        return dragEnd
    }

    func reset() {
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        canBeginTap = true
        requiresAllFingersReleased = false
        activeDragButton = nil
    }

    private func invalidateUntilAllFingersAreReleased() -> CompoundGestureEvent? {
        let dragEnd = activeDragButton.map(CompoundGestureEvent.dragEnded)
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        canBeginTap = false
        requiresAllFingersReleased = true
        activeDragButton = nil
        return dragEnd
    }

    private func makeTap(from touch: TrackedTouch) -> CompoundTap {
        let button: CompoundTapButton = touch.startPosition.x >= rightClickSplit ? .right : .left
        return CompoundTap(button: button, surfaceLocation: touch.startPosition)
    }

    private func processActiveDrag(
        touches: [CompoundTouch],
        timestamp: TimeInterval
    ) -> CompoundGestureEvent? {
        guard let activeDragButton,
              let tappingFinger else {
            reset()
            return nil
        }

        // Continue the drag regardless of finger movement or anchor loss.
        guard !touches.contains(where: { $0.identifier == tappingFinger.identifier }) else {
            return nil
        }

        self.activeDragButton = nil
        self.tappingFinger = nil
        tappingFingerWasRejected = false

        // Rebase a lone surviving anchor so another gesture can begin without
        // forcing a full release after the mouse has physically moved.
        if touches.count == 1,
           let previousAnchor = anchor,
           let currentAnchor = touches.first(where: { $0.identifier == previousAnchor.identifier }) {
            anchor = TrackedTouch(
                identifier: currentAnchor.identifier,
                startPosition: currentAnchor.position,
                startTime: timestamp
            )
            canBeginTap = true
        } else {
            anchor = nil
            canBeginTap = false
            requiresAllFingersReleased = true
        }

        return .dragEnded(activeDragButton)
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
