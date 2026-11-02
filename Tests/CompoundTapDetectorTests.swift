import CoreGraphics
import Darwin
import Foundation
import AppKit

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

private func expectMagnification(
    _ event: CompoundGestureEvent?,
    phase: CompoundMagnificationPhase,
    amount: CGFloat,
    tolerance: CGFloat = 0.000_001
) throws {
    guard case .magnify(let magnification) = event else {
        throw TestFailure(description: "Expected magnification event, got \(String(describing: event))")
    }
    try expectEqual(magnification.phase, phase)
    guard abs(magnification.amount - amount) <= tolerance else {
        throw TestFailure(description: "Expected magnification \(amount), got \(magnification.amount)")
    }
}

private func makeDetector(dragReleaseMode: DragReleaseMode = .holdThreeFingers) -> CompoundTapDetector {
    CompoundTapDetector(
        tapTimeThreshold: 0.28,
        movementThreshold: 0.04,
        rightClickSplit: 0.5,
        dragReleaseMode: dragReleaseMode
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

private func testDefaultDragEndsWhenAllThreeFingersLift() throws {
    let detector = makeDetector()
    let second = touch(identifier: 2, x: 0.25)
    let third = touch(identifier: 3, x: 0.75)
    try expectEqual(detector.configuration.dragReleaseMode, .holdThreeFingers)
    try expectEqual(
        detector.process(touches: [anchor, second, third], timestamp: 0),
        .dragBegan(CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5)))
    )
    try expectNil(detector.process(touches: [anchor, second], timestamp: 0.1))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.2))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [], timestamp: 0.3), .dragEnded(.left))
    try expectNil(detector.process(touches: [], timestamp: 0.4))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.5))
    try expectNil(detector.process(touches: [], timestamp: 0.6))
}

private func testCompoundTapEndsOnlyCombinedMode() throws {
    for mode: DragReleaseMode in [.singleFingerTap, .singleFingerTapOrCompoundTap] {
        let detector = makeDetector(dragReleaseMode: mode)
        let second = touch(identifier: 5, x: 0.25)
        _ = detector.process(touches: [anchor, touch(identifier: 2, x: 0.25), touch(identifier: 3, x: 0.75)], timestamp: 0)
        try expectNil(detector.process(touches: [], timestamp: 0.05))
        try expectNil(detector.process(touches: [anchor], timestamp: 1.0))
        try expectNil(detector.process(touches: [anchor, second], timestamp: 1.1))
        let result = detector.process(touches: [anchor], timestamp: 1.2)
        if mode == .singleFingerTapOrCompoundTap {
            try expectEqual(result, .dragEnded(.left))
            try expectNil(detector.process(touches: [], timestamp: 1.3))
            try expectNil(detector.activeDragButton)
        } else {
            try expectNil(result)
            try expectEqual(detector.activeDragButton, .left)
        }
    }
}

private func testCombinedModeStillAcceptsSingleFingerTap() throws {
    let detector = makeDetector(dragReleaseMode: .singleFingerTapOrCompoundTap)
    _ = detector.process(touches: [anchor, touch(identifier: 2, x: 0.25), touch(identifier: 3, x: 0.75)], timestamp: 0)
    try expectNil(detector.process(touches: [], timestamp: 0.05))
    try expectNil(detector.process(touches: [touch(identifier: 4, x: 0.5)], timestamp: 1.0))
    try expectEqual(detector.process(touches: [], timestamp: 1.1), .dragEnded(.left))
}

private func testCombinedModeRejectsInvalidCompoundTap() throws {
    let second = touch(identifier: 5, x: 0.25)
    let scenarios: [[(TimeInterval, [CompoundTouch])]] = [
        [(1.0, [anchor, second]), (1.1, [anchor])], // Both fingers land at once.
        [(1.0, [anchor]), (1.1, [anchor, second]), (1.5, [anchor])], // Too long.
        [(1.0, [anchor]), (1.1, [anchor, second]), (1.15, [anchor, touch(identifier: 5, x: 0.35)]), (1.2, [anchor])], // Second finger moves.
        [(1.0, [anchor]), (1.1, [anchor, second]), (1.15, [touch(identifier: 1, x: 0.6), second]), (1.2, [anchor])], // Anchor moves.
        [(1.0, [anchor]), (1.1, [anchor, second]), (1.2, [second])], // Anchor lifts first.
        [(1.0, [anchor]), (1.1, [anchor, second]), (1.15, [anchor, touch(identifier: 6, x: 0.25)]), (1.2, [anchor])], // Replacement.
        [(1.0, [anchor]), (1.1, [anchor, second, touch(identifier: 6, x: 0.75)]), (1.2, [anchor])]
    ]
    for frames in scenarios {
        let detector = makeDetector(dragReleaseMode: .singleFingerTapOrCompoundTap)
        _ = detector.process(touches: [anchor, touch(identifier: 2, x: 0.25), touch(identifier: 3, x: 0.75)], timestamp: 0)
        try expectNil(detector.process(touches: [], timestamp: 0.05))
        for (time, touches) in frames {
            try expectNil(detector.process(touches: touches, timestamp: time))
        }
        try expectEqual(detector.activeDragButton, .left)
        try expectNil(detector.process(touches: [], timestamp: 1.6))
        try expectNil(detector.process(touches: [anchor], timestamp: 2.0))
        try expectEqual(detector.process(touches: [], timestamp: 2.1), .dragEnded(.left))
    }
}

private func testThreeFingerDragStaysLatchedAcrossContactChanges() throws {
    let detector = makeDetector(dragReleaseMode: .singleFingerTap)
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
    try expectNil(detector.process(touches: [], timestamp: 0.15))
    try expectNil(detector.process(touches: [], timestamp: 8.0))
    try expectEqual(detector.gestureState, .dragging)
    try expectNil(detector.process(touches: [anchor, secondFinger, thirdFinger], timestamp: 8.1))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 8.2))
    try expectNil(detector.process(touches: [anchor], timestamp: 8.3))
    try expectNil(detector.process(touches: [], timestamp: 8.4))
    try expectEqual(detector.activeDragButton, .left)
}

private func startLatchedDrag() -> CompoundTapDetector {
    let detector = makeDetector(dragReleaseMode: .singleFingerTap)
    _ = detector.process(touches: [anchor, touch(identifier: 2, x: 0.25), touch(identifier: 3, x: 0.75)], timestamp: 0)
    _ = detector.process(touches: [], timestamp: 0.05)
    return detector
}

private func testSingleFingerTapDropsLatchedDragOnce() throws {
    let detector = startLatchedDrag()
    let finger = touch(identifier: 4, x: 0.8)
    try expectNil(detector.process(touches: [finger], timestamp: 1.0))
    try expectEqual(detector.activeDragButton, .left)
    try expectEqual(detector.process(touches: [], timestamp: 1.1), .dragEnded(.left))
    try expectEqual(detector.gestureState, .idle)
    try expectNil(detector.process(touches: [], timestamp: 1.2))
    // The drop produces only mouse-up; ordinary gestures work on the next touch.
    try expectNil(detector.process(touches: [anchor], timestamp: 1.3))
    try expectNil(detector.process(touches: [anchor, finger], timestamp: 1.4))
    try expectEqual(detector.process(touches: [anchor], timestamp: 1.5), .click(CompoundTap(button: .right, surfaceLocation: finger.position)))
    try expectEqual(detector.process(touches: [anchor, finger, touch(identifier: 5, x: 0.2)], timestamp: 1.6), .dragBegan(CompoundTap(button: .left, surfaceLocation: CGPoint(x: 0.5, y: 0.5))))
}

private func testDropRejectsLongMovingAndReplacementTouches() throws {
    let finger = touch(identifier: 4, x: 0.5)
    let scenarios: [([(TimeInterval, [CompoundTouch])], TimeInterval)] = [
        ([(1.0, [finger])], 1.5),
        ([(1.0, [finger]), (1.1, [touch(identifier: 4, x: 0.7)]), (1.15, [finger])], 1.2),
        ([(1.0, [finger]), (1.1, [touch(identifier: 5, x: 0.5)])], 1.2),
        ([(1.0, [finger]), (1.1, [finger, anchor]), (1.15, [finger])], 1.2),
        ([(1.0, [finger]), (0.9, [finger])], 1.1)
    ]
    for (frames, releaseTime) in scenarios {
        let detector = startLatchedDrag()
        for (timestamp, touches) in frames {
            try expectNil(detector.process(touches: touches, timestamp: timestamp))
        }
        try expectNil(detector.process(touches: [], timestamp: releaseTime))
        try expectEqual(detector.activeDragButton, .left)
        try expectNil(detector.process(touches: [finger], timestamp: 2.0))
        try expectEqual(detector.process(touches: [], timestamp: 2.1), .dragEnded(.left))
    }
}

private func testCancellingLatchedDragDiscardsPendingDropTap() throws {
    let detector = startLatchedDrag()
    try expectNil(detector.process(touches: [touch(identifier: 4, x: 0.5)], timestamp: 1.0))
    try expectEqual(detector.cancel(), .dragEnded(.left))
    try expectNil(detector.process(touches: [], timestamp: 1.1))
    try expectEqual(detector.gestureState, .idle)
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
    let movedFinger = touch(identifier: 2, x: 0.25, y: 0.55)

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
    let movedAnchor = touch(identifier: 1, x: 0.5, y: 0.55)
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
        rightClickSplit: 0.9,
        pinchStartThreshold: 0.5,
        pinchSensitivity: 10.0
    )

    try expectEqual(detector.configuration.tapTimeThreshold, 0.50)
    try expectEqual(detector.configuration.movementThreshold, 0.01)
    try expectEqual(detector.configuration.rightClickSplit, 0.75)
    try expectEqual(detector.configuration.pinchStartThreshold, 0.08)
    try expectEqual(detector.configuration.pinchSensitivity, 3.0)
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
    futureConfiguration.dragReleaseMode = .singleFingerTapOrCompoundTap
    futureConfiguration.pinchSensitivity = 2.25
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

private func testOldPresetsMigrateWithoutLosingTuning() throws {
    let suiteName = "com.mousetoucher.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let oldJSON = """
    [
      {"osVersion":"26.6.0","tapTimeThreshold":0.37,"movementThreshold":0.06,"rightClickSplit":0.65,"isThreeFingerDragEnabled":true},
      {"osVersion":"27.0.0","tapTimeThreshold":0.42,"movementThreshold":0.03,"rightClickSplit":0.55,"isThreeFingerDragEnabled":false,"isPinchZoomEnabled":false,"pinchStartThreshold":0.05,"pinchSensitivity":2.0}
    ]
    """
    defaults.set(Data(oldJSON.utf8), forKey: "osGesturePresets")
    defaults.set("26.6.0", forKey: "defaultPresetVersion")
    let settings = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(settings.configuration(for: "26.6.0")?.tapTimeThreshold, 0.37)
    try expectEqual(settings.activeConfiguration.tapTimeThreshold, 0.42)
    try expectEqual(settings.activeConfiguration.isThreeFingerDragEnabled, false)
    try expectEqual(settings.activeConfiguration.isPinchZoomEnabled, false)
    try expectEqual(settings.activeConfiguration.dragReleaseMode, .holdThreeFingers)
    try expectEqual(settings.activeConfiguration.pinchSensitivity, 2)
    try expectEqual(settings.defaultPresetVersion, "26.6.0")
    let reloaded = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(reloaded.activeConfiguration, settings.activeConfiguration)
    try expectEqual(reloaded.configuration(for: "26.6.0"), settings.configuration(for: "26.6.0"))
}

private func testRemovedModesMigrateWithoutLosingPresets() throws {
    let suiteName = "com.mousetoucher.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let modes = ["automatic", "macOS26", "releaseDelay", "explicitRelease", "macOS27", "hammerspoon"]
    let presets: [[String: Any]] = modes.enumerated().map { index, mode in
        ["osVersion": "27.0.\(index)", "tapTimeThreshold": 0.37,
         "movementThreshold": 0.06, "rightClickSplit": 0.65,
         "isThreeFingerDragEnabled": true, "dragCompatibility": mode,
         "dragReleaseDelay": 0.23]
    }
    defaults.set(try JSONSerialization.data(withJSONObject: presets), forKey: "osGesturePresets")
    defaults.set("27.0.0", forKey: "defaultPresetVersion")
    let settings = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(settings.presetVersions.count, modes.count)
    for index in modes.indices {
        let configuration = settings.configuration(for: "27.0.\(index)")
        try expectEqual(configuration?.tapTimeThreshold, 0.37)
        try expectEqual(configuration?.movementThreshold, 0.06)
    }
    let reloaded = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(reloaded.presetVersions, settings.presetVersions)
    let saved = defaults.data(forKey: "osGesturePresets")!
    let json = String(decoding: saved, as: UTF8.self)
    try expectEqual(json.contains("dragReleaseDelay"), false)
    try expectEqual(json.contains("dragCompatibility"), false)
    for removed in modes.prefix(4) { try expectEqual(json.contains(removed), false) }
}

private func testPreviousCombinedModeMigratesToCompoundTap() throws {
    let suiteName = "com.mousetoucher.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let oldJSON = """
    [{"osVersion":"27.0.1","tapTimeThreshold":0.37,"movementThreshold":0.06,"rightClickSplit":0.65,"isThreeFingerDragEnabled":true,"dragReleaseMode":"singleFingerTapOrPhysicalClick"}]
    """
    defaults.set(Data(oldJSON.utf8), forKey: "osGesturePresets")
    let settings = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.1")
    try expectEqual(settings.activeConfiguration.tapTimeThreshold, 0.37)
    try expectEqual(settings.activeConfiguration.dragReleaseMode, .singleFingerTapOrCompoundTap)
    let saved = String(decoding: defaults.data(forKey: "osGesturePresets")!, as: UTF8.self)
    try expectEqual(saved.contains("singleFingerTapOrPhysicalClick"), false)
    try expectEqual(saved.contains("singleFingerTapOrCompoundTap"), true)
}

private func testModernDragRunsBeforeWindowServerHandling() throws {
    try expectEqual(DragMotionEventMapper.tapLocation, .cghidEventTap)
    try expectEqual(DragMotionEventMapper.postLocation, .cgSessionEventTap)
    for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
        try expectEqual(DragMotionEventMapper.accepts(type), true)
        try expectEqual(DragMotionEventMapper.eventMask & (1 << type.rawValue) != 0, true)
    }
    for type: CGEventType in [.leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown] {
        try expectEqual(DragMotionEventMapper.accepts(type), false)
    }
}

private func testModernDragKeepsHardwareInputEnabled() throws {
    let factory = DragMouseEventFactory()
    guard let source = factory.source else {
        throw TestFailure(description: "Could not create modern drag source")
    }
    try expectEqual(source.localEventsSuppressionInterval, 0)
    for state: CGEventSuppressionState in [.eventSuppressionStateSuppressionInterval, .eventSuppressionStateRemoteMouseDrag] {
        let allowed = source.getLocalEventsFilterDuringSuppressionState(state)
        try expectEqual(allowed.contains(.permitLocalMouseEvents), true)
        try expectEqual(allowed.contains(.permitLocalKeyboardEvents), true)
    }
}

private func testModernDragCreatesFreshSessionEvents() throws {
    let factory = DragMouseEventFactory()
    let point = CGPoint(x: 415, y: 290)
    guard let motion = CGEvent(
        mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left
    ), let down = factory.buttonEvent(isDown: true, at: point, button: .left, clickCount: 1),
       let dragged = factory.freshDragEvent(from: motion, button: .left, clickCount: 1),
       let up = factory.buttonEvent(isDown: false, at: point, button: .left, clickCount: 1)
    else { throw TestFailure(description: "Could not create fresh drag sequence") }

    try expectEqual(motion.type, .mouseMoved)
    try expectEqual(dragged.type, .leftMouseDragged)
    try expectEqual(dragged.location, point)
    try expectEqual(dragged.getDoubleValueField(.mouseEventPressure), 1.0)
    try expectEqual(dragged.getIntegerValueField(.mouseEventClickState), 1)
    try expectEqual(dragged.getIntegerValueField(.eventSourceStateID), down.getIntegerValueField(.eventSourceStateID))
    try expectEqual(dragged.getIntegerValueField(.eventSourceStateID), up.getIntegerValueField(.eventSourceStateID))
}

private func testPinchProducesContinuousMagnification() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.70)
    let expandedFinger = touch(identifier: 2, x: 0.73)
    let expandedAgain = touch(identifier: 2, x: 0.74)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor, expandedFinger], timestamp: 0.08),
        .magnify(CompoundMagnification(phase: .began, amount: 0.08))
    )
    try expectEqual(detector.gestureState, .pinching)
    try expectMagnification(
        detector.process(touches: [anchor, expandedAgain], timestamp: 0.10),
        phase: .changed,
        amount: 0.05
    )
    try expectEqual(
        detector.process(touches: [anchor], timestamp: 0.12),
        .magnify(CompoundMagnification(phase: .ended, amount: 0))
    )
    try expectEqual(detector.gestureState, .anchorReady)
}

private func testPinchContractionProducesZoomOut() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.75)
    let contractedFinger = touch(identifier: 2, x: 0.71)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor, contractedFinger], timestamp: 0.08),
        .magnify(CompoundMagnification(phase: .began, amount: -0.08))
    )
}

private func testSimultaneousTouchesCanPinchButNeverClick() throws {
    let detector = makeDetector()
    let firstFinger = touch(identifier: 1, x: 0.35)
    let secondFinger = touch(identifier: 2, x: 0.65)
    let expandedFinger = touch(identifier: 2, x: 0.68)

    try expectNil(detector.process(touches: [firstFinger, secondFinger], timestamp: 0.00))
    try expectEqual(
        detector.process(touches: [firstFinger, expandedFinger], timestamp: 0.03),
        .magnify(CompoundMagnification(phase: .began, amount: 0.08))
    )
    try expectEqual(
        detector.process(touches: [firstFinger], timestamp: 0.06),
        .magnify(CompoundMagnification(phase: .ended, amount: 0))
    )

    let freshDetector = makeDetector()
    try expectNil(freshDetector.process(touches: [firstFinger, secondFinger], timestamp: 0.00))
    try expectNil(freshDetector.process(touches: [firstFinger], timestamp: 0.06))
}

private func testDisabledPinchFallsBackToTapRejection() throws {
    let detector = CompoundTapDetector(isPinchZoomEnabled: false)
    let secondFinger = touch(identifier: 2, x: 0.70)
    let movedFinger = touch(identifier: 2, x: 0.75)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 0.05))
    try expectNil(detector.process(touches: [anchor, movedFinger], timestamp: 0.08))
    try expectNil(detector.process(touches: [anchor], timestamp: 0.10))
    try expectEqual(detector.lastCancellationReason, .tapMoved)
}

private func testCancellingPinchEmitsEndedEvent() throws {
    let detector = makeDetector()
    let secondFinger = touch(identifier: 2, x: 0.70)
    let expandedFinger = touch(identifier: 2, x: 0.73)

    try expectNil(detector.process(touches: [anchor], timestamp: 0.00))
    try expectNil(detector.process(touches: [anchor, secondFinger], timestamp: 0.05))
    try expectEqual(
        detector.process(touches: [anchor, expandedFinger], timestamp: 0.08),
        .magnify(CompoundMagnification(phase: .began, amount: 0.08))
    )
    try expectEqual(
        detector.cancel(reason: .disabled),
        .magnify(CompoundMagnification(phase: .ended, amount: 0))
    )
    try expectNil(detector.cancel(reason: .disabled))
}

private func testNativeMagnificationEventShape() throws {
    let cases: [(CompoundMagnificationPhase, NSEvent.Phase)] = [
        (.began, .began),
        (.changed, .changed),
        (.ended, .ended)
    ]

    for (phase, expectedPhase) in cases {
        guard let cgEvent = NativeMagnificationEventFactory.makeEvent(
            phase: phase,
            amount: 0.03125,
            location: CGPoint(x: 100, y: 200)
        ), let event = NSEvent(cgEvent: cgEvent) else {
            throw TestFailure(description: "Could not create native magnification event")
        }

        try expectEqual(event.type, .magnify)
        try expectEqual(event.phase, expectedPhase)
        try expectEqual(event.magnification, 0.03125)
    }
}

private func testDragMotionUsesContinuousDraggedEventTypes() throws {
    try expectEqual(
        DragMotionEventMapper.eventType(for: .left),
        CGEventType.leftMouseDragged
    )
    try expectEqual(
        DragMotionEventMapper.eventType(for: .right),
        CGEventType.rightMouseDragged
    )
    try expectEqual(DragMotionEventMapper.buttonNumber(for: .left), 0)
    try expectEqual(DragMotionEventMapper.buttonNumber(for: .right), 1)
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
            ("default drag ends after all fingers lift", testDefaultDragEndsWhenAllThreeFingersLift),
            ("compound tap ends only combined release mode", testCompoundTapEndsOnlyCombinedMode),
            ("combined mode still accepts single-finger tap", testCombinedModeStillAcceptsSingleFingerTap),
            ("combined mode rejects invalid compound taps", testCombinedModeRejectsInvalidCompoundTap),
            ("drag stays latched through contact loss and recontact", testThreeFingerDragStaysLatchedAcrossContactChanges),
            ("single-finger tap drops once", testSingleFingerTapDropsLatchedDragOnce),
            ("drop rejects holds, movement, replacements and multitouch", testDropRejectsLongMovingAndReplacementTouches),
            ("cancel discards a pending drop tap", testCancellingLatchedDragDiscardsPendingDropTap),
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
            ("old presets migrate without losing tuning", testOldPresetsMigrateWithoutLosingTuning),
            ("removed modes migrate without losing presets", testRemovedModesMigrateWithoutLosingPresets),
            ("previous combined mode migrates to compound tap", testPreviousCombinedModeMigratesToCompoundTap),
            ("modern drag precedes WindowServer handling", testModernDragRunsBeforeWindowServerHandling),
            ("modern drag permits hardware input", testModernDragKeepsHardwareInputEnabled),
            ("modern drag creates fresh session events", testModernDragCreatesFreshSessionEvents),
            ("pinch produces continuous magnification", testPinchProducesContinuousMagnification),
            ("pinch contraction zooms out", testPinchContractionProducesZoomOut),
            ("simultaneous touches can only pinch", testSimultaneousTouchesCanPinchButNeverClick),
            ("disabled pinch rejects movement", testDisabledPinchFallsBackToTapRejection),
            ("cancelling pinch emits end", testCancellingPinchEmitsEndedEvent),
            ("native magnification event shape", testNativeMagnificationEventShape),
            ("drag motion uses dragged event types", testDragMotionUsesContinuousDraggedEventTypes),
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
