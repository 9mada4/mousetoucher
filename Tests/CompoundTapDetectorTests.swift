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

private func testDragCompatibilitySelection() throws {
    try expectEqual(DragCompatibilityMode.automatic.resolved(systemMajorVersion: 11), .macOS26)
    try expectEqual(DragCompatibilityMode.automatic.resolved(systemMajorVersion: 26), .macOS26)
    try expectEqual(DragCompatibilityMode.automatic.resolved(systemMajorVersion: 27), .macOS27)
    try expectEqual(DragCompatibilityMode.automatic.resolved(systemMajorVersion: 28), .macOS27)
    try expectEqual(DragCompatibilityMode.macOS26.resolved(systemMajorVersion: 27), .macOS26)
    try expectEqual(DragCompatibilityMode.macOS27.resolved(systemMajorVersion: 26), .macOS27)
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
    try expectEqual(settings.configuration(for: "26.6.0")?.dragCompatibility, .macOS26)
    try expectEqual(settings.configuration(for: "26.6.0")?.tapTimeThreshold, 0.37)
    try expectEqual(settings.activeConfiguration.dragCompatibility, .automatic)
    try expectEqual(settings.activeConfiguration.tapTimeThreshold, 0.42)
    try expectEqual(settings.activeConfiguration.isThreeFingerDragEnabled, false)
    try expectEqual(settings.activeConfiguration.isPinchZoomEnabled, false)
    try expectEqual(settings.activeConfiguration.pinchSensitivity, 2)
    try expectEqual(settings.defaultPresetVersion, "26.6.0")
    let reloaded = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(reloaded.activeConfiguration, settings.activeConfiguration)
    try expectEqual(reloaded.configuration(for: "26.6.0"), settings.configuration(for: "26.6.0"))
}

private func testExplicitLegacyModePersistsAndAppliesOn27() throws {
    let suiteName = "com.mousetoucher.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = MouseToucherSettings(defaults: defaults, currentOSVersion: "26.6.0")
    var legacy = settings.activeConfiguration
    legacy.dragCompatibility = .macOS26
    legacy.tapTimeThreshold = 0.36
    _ = settings.updateConfiguration(legacy, for: "26.6.0")
    let upgraded = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(upgraded.activeConfiguration.dragCompatibility, .automatic)
    try expectEqual(upgraded.activeConfiguration.tapTimeThreshold, 0.36)
    try expectEqual(upgraded.configuration(for: "26.6.0"), legacy)
    try expectEqual(upgraded.applyPresetToCurrentOS(version: "26.6.0"), legacy)
    let reloaded = MouseToucherSettings(defaults: defaults, currentOSVersion: "27.0.0")
    try expectEqual(reloaded.activeConfiguration, legacy)
    _ = reloaded.resetPreset(version: "27.0.0")
    try expectEqual(reloaded.activeConfiguration.dragCompatibility, .automatic)
}

private func testCompatibilitySwitchEndsDragExactlyOnce() throws {
    let detector = makeDetector()
    _ = detector.process(touches: [anchor, touch(identifier: 2, x: 0.25), touch(identifier: 3, x: 0.75)], timestamp: 0)
    var changed = detector.configuration
    changed.dragCompatibility = .macOS26
    try expectEqual(detector.updateConfiguration(changed), .dragEnded(.left))
    try expectEqual(detector.lastCancellationReason, .settingsChanged)
    try expectNil(detector.updateConfiguration(changed))
    try expectNil(detector.process(touches: [], timestamp: 0.1))
}

private func testModernDragRunsBeforeWindowServerHandling() throws {
    try expectEqual(DragMotionEventMapper.tapLocation(for: .macOS27), .cghidEventTap)
    try expectEqual(DragMotionEventMapper.tapLocation(for: .macOS26), .cgSessionEventTap)
    for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
        try expectEqual(DragMotionEventMapper.accepts(type, mode: .macOS27), true)
        try expectEqual(DragMotionEventMapper.eventMask(for: .macOS27) & (1 << type.rawValue) != 0, true)
        try expectEqual(DragMotionEventMapper.accepts(type, mode: .macOS26), type == .mouseMoved)
    }
    for type: CGEventType in [.leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown] {
        try expectEqual(DragMotionEventMapper.accepts(type, mode: .macOS27), false)
    }
}

private func testModernDragKeepsHardwareInputEnabled() throws {
    let factory = DragMouseEventFactory(mode: .macOS27)
    guard let source = factory.source else {
        throw TestFailure(description: "Could not create modern drag source")
    }
    try expectEqual(source.localEventsSuppressionInterval, 0)
    for state: CGEventSuppressionState in [.eventSuppressionStateSuppressionInterval, .eventSuppressionStateRemoteMouseDrag] {
        let allowed = source.getLocalEventsFilterDuringSuppressionState(state)
        try expectEqual(allowed.contains(.permitLocalMouseEvents), true)
        try expectEqual(allowed.contains(.permitLocalKeyboardEvents), true)
    }
    try expectNil(DragMouseEventFactory(mode: .macOS26).source)
}

private func testDragEventsPreserveMotionAndPairButtons() throws {
    for mode: DragCompatibilityMode in [.macOS26, .macOS27] {
        let factory = DragMouseEventFactory(mode: mode)
        for button: CompoundTapButton in [.left, .right] {
            let point = CGPoint(x: -250, y: 140)
            guard let down = factory.buttonEvent(isDown: true, at: point, button: button, clickCount: 1),
                  let up = factory.buttonEvent(isDown: false, at: point, button: button, clickCount: 1),
                  let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
                throw TestFailure(description: "Could not create drag events")
            }
            move.setIntegerValueField(.mouseEventDeltaX, value: -8)
            move.setIntegerValueField(.mouseEventDeltaY, value: 12)
            move.flags = [.maskShift, .maskAlternate]
            let timestamp = move.timestamp
            factory.convertMotion(move, button: button, clickCount: 1)
            try expectEqual(move.type, button == .left ? .leftMouseDragged : .rightMouseDragged)
            try expectEqual(move.location, point)
            try expectEqual(move.timestamp, timestamp)
            try expectEqual(move.flags, [.maskShift, .maskAlternate])
            try expectEqual(move.getIntegerValueField(.mouseEventDeltaX), -8)
            try expectEqual(move.getIntegerValueField(.mouseEventDeltaY), 12)
            try expectEqual(move.getIntegerValueField(.mouseEventButtonNumber), button == .left ? 0 : 1)
            try expectEqual(down.type, button == .left ? .leftMouseDown : .rightMouseDown)
            try expectEqual(up.type, button == .left ? .leftMouseUp : .rightMouseUp)
            try expectEqual(down.getIntegerValueField(.eventSourceStateID), up.getIntegerValueField(.eventSourceStateID))
            if mode == .macOS27 {
                try expectEqual(move.getIntegerValueField(.eventSourceStateID), down.getIntegerValueField(.eventSourceStateID))
            }
        }
    }
}

private final class FakeWindowDragTarget: WindowDragTarget {
    let origin: CGPoint
    var positions: [CGPoint] = []
    var acceptsMovement = true
    init(origin: CGPoint) { self.origin = origin }
    func move(to point: CGPoint) -> Bool {
        positions.append(point)
        return acceptsMovement
    }
}

private func testWindowDragRejectsControlsAndContent() throws {
    let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    let cursor = CGPoint(x: 300, y: 112)
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: cursor, frame: frame, closeButtonFrame: nil, roles: ["AXWindow"]), true)
    for role in ["AXButton", "AXTextField", "AXTabGroup", "AXRadioButton", "AXScrollArea", "AXWebArea", "AXUnknown"] {
        try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: cursor, frame: frame, closeButtonFrame: nil, roles: ["AXStaticText", role, "AXWindow"]), false)
    }
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: CGPoint(x: 300, y: 200), frame: frame, closeButtonFrame: nil, roles: ["AXGroup", "AXWindow"]), false)
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: CGPoint(x: 20, y: 112), frame: frame, closeButtonFrame: nil, roles: ["AXWindow"]), false)
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: cursor, frame: frame, closeButtonFrame: nil, roles: []), false)
}

private func testUnifiedTitleBarAndNegativeCoordinates() throws {
    let frame = CGRect(x: -1000, y: -500, width: 800, height: 600)
    let close = CGRect(x: -988, y: -479, width: 14, height: 14)
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: CGPoint(x: -800, y: -455), frame: frame, closeButtonFrame: close, roles: ["AXStaticText", "AXToolbar", "AXWindow"]), true)
    try expectEqual(WindowDragGeometry.isTitleBarHit(cursor: CGPoint(x: -800, y: -400), frame: frame, closeButtonFrame: close, roles: ["AXWindow"]), false)
}

private func testWindowDragFollowsCursorWithoutAccumulatedDrift() throws {
    let target = FakeWindowDragTarget(origin: CGPoint(x: -900, y: -400))
    let session = WindowDragSession()
    session.begin(target: target, cursor: CGPoint(x: -800, y: -386))
    try expectEqual(session.update(cursor: CGPoint(x: -700, y: -286)), true)
    try expectEqual(target.positions.last, CGPoint(x: -800, y: -300))
    try expectEqual(session.update(cursor: CGPoint(x: -750, y: -336)), true)
    try expectEqual(target.positions.last, CGPoint(x: -850, y: -350))
    _ = session.update(cursor: CGPoint(x: -750, y: -336))
    try expectEqual(target.positions.count, 2)
    session.end()
    session.end()
    try expectEqual(session.update(cursor: .zero), false)
    try expectEqual(target.positions.count, 2)
}

private func testWindowDragStopsAfterTargetFailure() throws {
    let target = FakeWindowDragTarget(origin: .zero)
    let session = WindowDragSession()
    session.begin(target: target, cursor: .zero)
    target.acceptsMovement = false
    try expectEqual(session.update(cursor: CGPoint(x: 30, y: 20)), false)
    try expectEqual(session.isActive, false)
    try expectEqual(session.update(cursor: CGPoint(x: 90, y: 20)), false)
    try expectEqual(target.positions.count, 1)
    let next = FakeWindowDragTarget(origin: CGPoint(x: 200, y: 100))
    session.begin(target: next, cursor: CGPoint(x: 300, y: 110))
    _ = session.update(cursor: CGPoint(x: 310, y: 110))
    try expectEqual(next.positions.last, CGPoint(x: 210, y: 100))
    try expectEqual(target.positions.count, 1)
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
            ("compatibility follows OS or explicit override", testDragCompatibilitySelection),
            ("old presets migrate without losing tuning", testOldPresetsMigrateWithoutLosingTuning),
            ("legacy mode persists and applies on macOS 27", testExplicitLegacyModePersistsAndAppliesOn27),
            ("compatibility switch ends drag exactly once", testCompatibilitySwitchEndsDragExactlyOnce),
            ("modern drag precedes WindowServer handling", testModernDragRunsBeforeWindowServerHandling),
            ("modern drag permits hardware input", testModernDragKeepsHardwareInputEnabled),
            ("drag events preserve motion and pair buttons", testDragEventsPreserveMotionAndPairButtons),
            ("window dragging excludes controls and document content", testWindowDragRejectsControlsAndContent),
            ("unified title bars support negative screen coordinates", testUnifiedTitleBarAndNegativeCoordinates),
            ("window position follows cursor and stops on release", testWindowDragFollowsCursorWithoutAccumulatedDrift),
            ("failed window movement stops without retargeting", testWindowDragStopsAfterTargetFailure),
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
