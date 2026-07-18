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

/// Recognizes a quick tap made while another finger remains stationary.
///
/// The first finger becomes the anchor. A second finger must touch and release
/// without either finger moving beyond the configured threshold. The anchor
/// remains active after a successful tap so it can be reused for consecutive
/// clicks, including double-clicks.
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

    init(
        tapTimeThreshold: TimeInterval = 0.28,
        movementThreshold: CGFloat = 0.04,
        rightClickSplit: CGFloat = 0.5
    ) {
        self.tapTimeThreshold = tapTimeThreshold
        self.movementThreshold = movementThreshold
        self.rightClickSplit = rightClickSplit
    }

    func process(touches: [CompoundTouch], timestamp: TimeInterval) -> CompoundTap? {
        if touches.isEmpty {
            reset()
            return nil
        }

        guard !requiresAllFingersReleased else { return nil }

        guard let anchor else {
            guard touches.count == 1, let firstTouch = touches.first else {
                invalidateUntilAllFingersAreReleased()
                return nil
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
            invalidateUntilAllFingersAreReleased()
            return nil
        }

        guard distance(from: anchor.startPosition, to: currentAnchor.position) <= movementThreshold else {
            invalidateUntilAllFingersAreReleased()
            return nil
        }

        let secondaryTouches = touches.filter { $0.identifier != anchor.identifier }
        guard secondaryTouches.count <= 1 else {
            invalidateUntilAllFingersAreReleased()
            return nil
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
            if duration < 0 ||
                duration > tapTimeThreshold ||
                distance(from: tappingFinger.startPosition, to: currentTap.position) > movementThreshold {
                tappingFingerWasRejected = true
            }
            return nil
        }

        // Accept another tap only after a clean anchor-only frame. This prevents
        // a replacement touch identifier from being interpreted as a release.
        guard secondaryTouches.isEmpty else {
            self.tappingFinger = nil
            tappingFingerWasRejected = false
            canBeginTap = false
            return nil
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

        let button: CompoundTapButton = tappingFinger.startPosition.x >= rightClickSplit ? .right : .left
        return CompoundTap(button: button, surfaceLocation: tappingFinger.startPosition)
    }

    func reset() {
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        canBeginTap = true
        requiresAllFingersReleased = false
    }

    private func invalidateUntilAllFingersAreReleased() {
        anchor = nil
        tappingFinger = nil
        tappingFingerWasRejected = false
        canBeginTap = false
        requiresAllFingersReleased = true
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
