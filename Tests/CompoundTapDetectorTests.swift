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

private func testHoldingSecondFingerDoesNotBeginDrag() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.25))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.34))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.40))
    try expectNil(detector.activeDragButton)
}

private func testCancelEndsActiveDragExactlyOnce() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)
    let drag = CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5))

    try expectEqual(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.00),
        .dragBegan(drag)
    )
    try expectEqual(detector.cancel(), .dragEnded(.left))
    try expectNil(detector.cancel())
}

private func testThreeFingerDragContinuesUntilEveryFingerLifts() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)
    let movedFirst = touch(identifier: 1, x: 0.90)
    let movedSecond = touch(identifier: 2, x: 0.05)
    let drag = CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5))

    try expectEqual(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.00),
        .dragBegan(drag)
    )
    try expectNil(detector.process(touches: [movedFirst, movedSecond], timestamp: 0.05))
    try expectNil(detector.process(touches: [thirdFinger], timestamp: 0.10))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [], timestamp: 0.15), .dragEnded(.left))
}

private func testThirdFingerStartsDragDuringCompoundTap() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)
    let drag = CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5))

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.06),
        .dragBegan(drag)
    )
}

private func testAnchorCanDriftBetweenTapsWithoutBeingLifted() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let movedAnchor = touch(identifier: 1, x: 0.56)
    let tap = CompoundTap(button: .left, surfaceLocation: tappingFinger.position)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(detector.process(touches: [anchor], timestamp: 0.10), .click(tap))
    try expectNil(detector.process(touches: [movedAnchor], timestamp: 0.15))
    try expectNil(detector.process(touches: [movedAnchor, tappingFinger], timestamp: 0.20))
    try expectEqual(detector.process(touches: [movedAnchor], timestamp: 0.25), .click(tap))
}

private func testMovingTappingFingerIsRejected() throws {
    let detector = makeDetector()
    let tappingFinger = touch(identifier: 2, x: 0.25)
    let movedFinger = touch(identifier: 2, x: 0.30)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, movedFinger], timestamp: 0.10))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.12))

    // The same anchor can immediately accept a new tap.
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.15))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.20),
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )
}

private func testMovingAnchorDuringTapRejectsOnlyThatTap() throws {
    let detector = makeDetector()
    let movedAnchor = touch(identifier: 1, x: 0.55)
    let tappingFinger = touch(identifier: 2, x: 0.25)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [movedAnchor, tappingFinger], timestamp: 0.10))
    try expectNil(detector.process(touches: [movedAnchor], timestamp: 0.15))

    // A second tap works while the anchor remains down.
    try expectNil(detector.process(touches: [movedAnchor, tappingFinger], timestamp: 0.20))
    try expectEqual(
        detector.process(touches: [movedAnchor], timestamp: 0.25),
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

private func testThreeFingerContactBeginsDragImmediately() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)
    let drag = CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5))

    try expectEqual(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.00),
        .dragBegan(drag)
    )
    try expectEqual(detector.activeDragButton, .left)
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

private func testConfigurationValuesAreClamped() throws {
    let detector = CompoundTapDetector(
        tapTimeThreshold: 2.0,
        movementThreshold: 0.0,
        rightClickSplit: 0.9
    )

    try expectEqual(detector.configuration.tapTimeThreshold, 0.50)
    try expectEqual(detector.configuration.movementThreshold, 0.01)
    try expectEqual(detector.configuration.rightClickSplit, 0.75)
}

private func testCustomRightClickSplitIsApplied() throws {
    let detector = CompoundTapDetector(rightClickSplit: 0.7)
    let tappingFinger = touch(identifier: 2, x: 0.6)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, tappingFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.10),
        .click(CompoundTap(button: .left, surfaceLocation: tappingFinger.position))
    )
}

private func testDisabledThreeFingerDragReportsReason() throws {
    let detector = CompoundTapDetector(isThreeFingerDragEnabled: false)
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)

    try expectNil(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.00)
    )
    try expectEqual(detector.gestureState, .waitingForRelease)
    try expectEqual(detector.lastCancellationReason, .threeFingerDragDisabled)
    try expectNil(detector.process(touches: [], timestamp: 0.05))
    try expectEqual(detector.gestureState, .idle)
}

private func testConfigurationChangeEndsActiveDrag() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.25)
    let thirdFinger = touch(identifier: 3, x: 0.75)

    try expectEqual(
        detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 0.00),
        .dragBegan(CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5)))
    )

    var changed = CompoundGestureConfiguration.default
    changed.tapTimeThreshold = 0.35
    try expectEqual(detector.updateConfiguration(changed), .dragEnded(.left))
    try expectEqual(detector.lastCancellationReason, .settingsChanged)
    try expectEqual(detector.gestureState, .idle)
}

private func testOSPresetsFollowCurrentSystemVersion() throws {
    let suiteName = "com.mousetoucher.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = MouseToucherSettings(defaults: defaults, currentOSVersion: "26.5.2")
    try expectEqual(settings.presetVersions, ["26.5.2"])

    try expectEqual(settings.addPreset(version: "27.0.0", copying: "26.5.2"), true)
    var futureConfiguration = CompoundGestureConfiguration.default
    futureConfiguration.tapTimeThreshold = 0.42
    futureConfiguration.isThreeFingerDragEnabled = false
    try expectEqual(
        settings.updateConfiguration(futureConfiguration, for: "27.0.0"),
        false
    )
    try expectEqual(settings.setDefaultPreset(version: "27.0.0"), true)

    let afterUpgrade = MouseToucherSettings(defaults: defaults, currentOSVersion: "28.0.0")
    try expectEqual(afterUpgrade.activeConfiguration, futureConfiguration)
    try expectEqual(afterUpgrade.presetVersions, ["26.5.2", "27.0.0", "28.0.0"])

    let applied = afterUpgrade.applyPresetToCurrentOS(version: "26.5.2")
    try expectEqual(applied, CompoundGestureConfiguration.default)
    try expectEqual(afterUpgrade.activeConfiguration, .default)
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
            ("holding second finger does not drag", testHoldingSecondFingerDoesNotBeginDrag),
            ("cancel ends drag once", testCancelEndsActiveDragExactlyOnce),
            ("three-finger drag survives partial contact", testThreeFingerDragContinuesUntilEveryFingerLifts),
            ("third finger starts drag during tap", testThirdFingerStartsDragDuringCompoundTap),
            ("anchor can drift between taps", testAnchorCanDriftBetweenTapsWithoutBeingLifted),
            ("moving tapping finger is rejected", testMovingTappingFingerIsRejected),
            ("moving anchor rejects one tap", testMovingAnchorDuringTapRejectsOnlyThatTap),
            ("anchor release cancels tap", testReleasingAnchorBeforeTappingFingerDoesNotClick),
            ("three fingers begin drag immediately", testThreeFingerContactBeginsDragImmediately),
            ("replacement finger is rejected", testReplacementFingerIsNotTreatedAsTapRelease),
            ("configuration values are clamped", testConfigurationValuesAreClamped),
            ("custom right-click split is applied", testCustomRightClickSplitIsApplied),
            ("disabled drag reports its reason", testDisabledThreeFingerDragReportsReason),
            ("configuration change ends drag", testConfigurationChangeEndsActiveDrag),
            ("OS presets follow the current version", testOSPresetsFollowCurrentSystemVersion),
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
