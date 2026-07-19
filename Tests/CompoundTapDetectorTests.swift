import CoreGraphics
import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String = ""
) throws {
    guard actual == expected else {
        let detail = message.isEmpty ? "Expected \(expected), got \(actual)" : message
        throw TestFailure(description: detail)
    }
}

private func expectNil<T>(_ value: T?, _ message: String = "Expected nil") throws {
    guard value == nil else {
        throw TestFailure(description: message)
    }
}

private func makeDetector() -> CompoundTapDetector {
    CompoundTapDetector(
        tapTimeThreshold: 0.28,
        movementThreshold: 0.04,
        rightClickSplit: 0.5
    )
}

private let anchor = CompoundTouch(identifier: 1, position: CGPoint(x: 0.5, y: 0.5))

private func touch(identifier: Int32, x: CGFloat, y: CGFloat = 0.5) -> CompoundTouch {
    CompoundTouch(identifier: identifier, position: CGPoint(x: x, y: y))
}

private func testSingleFingerTapDoesNotClick() throws {
    let detector = makeDetector()

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [], timestamp: 0.10))
}

private func testSecondFingerOnLeftCreatesLeftClick() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))

    let result = detector.process(touches: [anchor], timestamp: 0.12)
    try expectEqual(
        result,
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )
}

private func testSecondFingerOnRightCreatesRightClick() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.75)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))

    let result = detector.process(touches: [anchor], timestamp: 0.12)
    try expectEqual(
        result,
        .click(CompoundTap(button: .right, surfaceLocation: tappingFinger.position))
    )
}

private func testCenterBelongsToRightSide() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.5)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.12),
        .click(CompoundTap(button: .right, surfaceLocation: tappingFinger.position))
    )
}

private func testAnchorCanBeReusedForConsecutiveClicks() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.10),
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )

    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.15))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.20),
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )
}

private func testHoldingSecondFingerBeginsAndEndsDrag() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let tap = CompoundTap(button: .left, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.25))
    try expectEqual(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34), .dragBegan(tap))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [anchor], timestamp: 0.40), .dragEnded(.left))
    try expectNil(detector.activeDragButton)
}

private func testCancelEndsActiveDragExactlyOnce() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.75)
    let tap = CompoundTap(button: .right, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34), .dragBegan(tap))
    try expectEqual(detector.cancel(), .dragEnded(.right))
    try expectNil(detector.cancel())
}

private func testMovingAnchorDoesNotInterruptActiveDrag() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let movedAnchor = touch(identifier: 1, x: 0.55)
    let tap = CompoundTap(button: .left, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34), .dragBegan(tap))
    try expectNil(detector.process(touches: [movedAnchor, tappingFinger], timestamp: 0.36))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [movedAnchor], timestamp: 0.40), .dragEnded(.left))

    // The moved anchor is rebased and can immediately be reused.
    try expectNil(detector.process(touches: [movedAnchor, tappingFinger], timestamp: 0.45))
    try expectEqual(
        detector.process(touches: [movedAnchor], timestamp: 0.50),
        .click(tap)
    )
}

private func testMovingHeldFingerDoesNotInterruptActiveDrag() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let movedTappingFinger = touch(identifier: 2, x: 0.40)
    let tap = CompoundTap(button: .left, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34), .dragBegan(tap))
    try expectNil(detector.process(touches: [anchor, movedTappingFinger], timestamp: 0.36))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [anchor], timestamp: 0.40), .dragEnded(.left))
}

private func testAnchorMayLiftDuringActiveDrag() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let tap = CompoundTap(button: .left, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34), .dragBegan(tap))
    try expectNil(detector.process(touches: [tappingFinger], timestamp: 0.36))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [], timestamp: 0.40), .dragEnded(.left))
}

private func testMovingTappingFingerIsRejected() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let movedFinger = touch(identifier: 2, x: 0.30)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, movedFinger], timestamp: 0.10))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.12))
}

private func testMovingAnchorInvalidatesGestureUntilAllFingersLift() throws {
    let detector = makeDetector()
    let movedAnchor = touch(identifier: 1, x: 0.55)
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [movedAnchor], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.10))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.15))

    try expectNil(detector.process(touches: [], timestamp: 0.20))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.25))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.30))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.35),
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )
}

private func testReleasingAnchorBeforeTappingFingerDoesNotClick() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [tappingFinger], timestamp: 0.10))
    try expectNil(detector.process(touches: [], timestamp: 0.12))
}

private func testThirdFingerInvalidatesGesture() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.10))
}

private func testReplacementFingerIsNotTreatedAsTapRelease() throws {
    let detector = makeDetector()
    let firstTap = touch(identifier: 2, x: 0.25)
    let replacement = touch(identifier: 3, x: 0.75)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, firstTap], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, replacement], timestamp: 0.10))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.12))
}

private func testConsecutiveClicksIncrementClickCount() throws {
    var tracker = ClickSequenceTracker(doubleClickInterval: 0.5)
    let location = CGPoint(x: 100, y: 100)

    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.0), 1)
    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.2), 2)
    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.4), 3)
}

private func testDifferentButtonStartsNewSequence() throws {
    var tracker = ClickSequenceTracker(doubleClickInterval: 0.5)
    let location = CGPoint(x: 100, y: 100)

    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.0), 1)
    try expectEqual(tracker.nextClickCount(button: .right, location: location, timestamp: 0.2), 1)
}

private func testExpiredIntervalStartsNewSequence() throws {
    var tracker = ClickSequenceTracker(doubleClickInterval: 0.5)
    let location = CGPoint(x: 100, y: 100)

    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.0), 1)
    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.51), 1)
}

private func testLargeCursorMovementStartsNewSequence() throws {
    var tracker = ClickSequenceTracker(doubleClickInterval: 0.5, maximumCursorMovement: 5.0)
    let location = CGPoint(x: 100, y: 100)

    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.0), 1)
    try expectEqual(
        tracker.nextClickCount(button: .left, location: CGPoint(x: 106, y: 100), timestamp: 0.2),
        1
    )
}

private func testResetStartsNewSequence() throws {
    var tracker = ClickSequenceTracker(doubleClickInterval: 0.5)
    let location = CGPoint(x: 100, y: 100)

    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.0), 1)
    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.2), 2)
    tracker.reset()
    try expectEqual(tracker.nextClickCount(button: .left, location: location, timestamp: 0.3), 1)
}

@main
private enum CompoundTapTestRunner {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("single-finger tap is ignored", testSingleFingerTapDoesNotClick),
            ("left compound tap", testSecondFingerOnLeftCreatesLeftClick),
            ("right compound tap", testSecondFingerOnRightCreatesRightClick),
            ("center split", testCenterBelongsToRightSide),
            ("consecutive taps reuse anchor", testAnchorCanBeReusedForConsecutiveClicks),
            ("hold begins and ends drag", testHoldingSecondFingerBeginsAndEndsDrag),
            ("cancel ends drag once", testCancelEndsActiveDragExactlyOnce),
            ("moving anchor does not interrupt drag", testMovingAnchorDoesNotInterruptActiveDrag),
            ("moving held finger does not interrupt drag", testMovingHeldFingerDoesNotInterruptActiveDrag),
            ("anchor may lift during drag", testAnchorMayLiftDuringActiveDrag),
            ("moving tapping finger is rejected", testMovingTappingFingerIsRejected),
            ("moving anchor requires full release", testMovingAnchorInvalidatesGestureUntilAllFingersLift),
            ("anchor release cancels tap", testReleasingAnchorBeforeTappingFingerDoesNotClick),
            ("third finger cancels gesture", testThirdFingerInvalidatesGesture),
            ("replacement finger is rejected", testReplacementFingerIsNotTreatedAsTapRelease),
            ("click count increments", testConsecutiveClicksIncrementClickCount),
            ("button change resets click count", testDifferentButtonStartsNewSequence),
            ("expired interval resets click count", testExpiredIntervalStartsNewSequence),
            ("cursor movement resets click count", testLargeCursorMovementStartsNewSequence),
            ("manual reset resets click count", testResetStartsNewSequence)
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name) — \(error)")
            }
        }

        print("\n\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 {
            exit(EXIT_FAILURE)
        }
    }
}
