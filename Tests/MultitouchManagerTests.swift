import CoreGraphics
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

private let threeTouches = [
    CompoundTouch(identifier: 1, position: CGPoint(x: 0.5, y: 0.5)),
    CompoundTouch(identifier: 2, position: CGPoint(x: 0.25, y: 0.5)),
    CompoundTouch(identifier: 3, position: CGPoint(x: 0.75, y: 0.5))
]

private final class Fixture {
    let first = MTDeviceRef(bitPattern: 1)!
    let replacement = MTDeviceRef(bitPattern: 2)!
    var nextDevices: [MTDeviceRef]?
    var snapshotCount = 0
    var started: [MTDeviceRef] = []
    var stopped: [MTDeviceRef] = []
    var duringSnapshot: (() -> Void)?
    var duringStart: (() -> Void)?
    var events: [CompoundGestureEvent] = []
    var manager: MultitouchManager!

    init(dragReleaseMode: DragReleaseMode = .singleFingerTap) {
        nextDevices = [first]
        var configuration = CompoundGestureConfiguration.default
        configuration.dragReleaseMode = dragReleaseMode
        manager = MultitouchManager(
            configuration: configuration,
            deviceAccess: MultitouchDeviceAccess(
                snapshot: { [unowned self] in
                    snapshotCount += 1
                    duringSnapshot?()
                    return nextDevices.map { MultitouchDeviceSnapshot(devices: $0, retainedList: nil) }
                },
                start: { [unowned self] in
                    started.append($0)
                    duringStart?()
                },
                stop: { [unowned self] in stopped.append($0) }
            ),
            physicalButtonIsPressed: { false }
        )
        manager.onGestureRecognized = { [unowned self] _, event in events.append(event) }
        manager.start()
    }

    func close() {
        duringSnapshot = nil
        duringStart = nil
        manager.onGestureRecognized = nil
        manager.stop()
    }

    func beginDrag() { manager.processTouches(threeTouches, timestamp: 0) }

    func drop() {
        manager.processTouches([], timestamp: 30)
        manager.processTouches([threeTouches[0]], timestamp: 30.1)
        manager.processTouches([], timestamp: 30.2)
    }

    var endCount: Int { events.filter { $0 == .dragEnded(.left) }.count }
}

private func testRefreshPreservesLatchedDrag() throws {
    let fixture = Fixture()
    defer { fixture.close() }
    fixture.beginDrag()
    fixture.nextDevices = [fixture.replacement]
    for (index, touches) in [threeTouches, [], threeTouches, [], [threeTouches[0]]].enumerated() {
        fixture.manager.processTouches(touches, timestamp: Double(index) * 5)
        fixture.manager.refreshDevices()
    }
    try expect(fixture.snapshotCount == 1, "Periodic refresh must not enumerate during a latched drag")
    try expect(fixture.stopped.isEmpty, "Periodic refresh must not unregister active drag callbacks")
    try expect(fixture.endCount == 0, "Contact changes and periodic refresh must not release a drag")
    fixture.drop()
    try expect(fixture.endCount == 1, "A fresh single-finger tap must still release the drag")
    fixture.manager.refreshDevices()
    try expect(fixture.snapshotCount == 2, "Refresh must resume after dropping")
    try expect(fixture.stopped == [fixture.first], "The old device must stop after dropping")
    try expect(fixture.started == [fixture.first, fixture.replacement], "Reconnect monitoring must resume")
    try expect(fixture.endCount == 1, "Refreshing after a drop must not send another release")
}

private func testEnumerationFailureDuringDragIsDeferred() throws {
    let fixture = Fixture()
    defer { fixture.close() }
    fixture.beginDrag()
    fixture.nextDevices = nil
    fixture.manager.refreshDevices()
    try expect(fixture.snapshotCount == 1 && fixture.stopped.isEmpty && fixture.endCount == 0,
               "Unavailable enumeration must not affect a latched drag")
    fixture.drop()
    fixture.manager.refreshDevices()
    try expect(fixture.stopped == [fixture.first], "Idle enumeration failure must still stop stale monitoring")
}

private func testDragBeginningDuringEnumerationIsPreserved() throws {
    for devicesUnavailable in [false, true] {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.nextDevices = devicesUnavailable ? nil : [fixture.replacement]
        fixture.duringSnapshot = { fixture.beginDrag() }
        fixture.manager.refreshDevices()
        try expect(fixture.events.count == 1, "Enumeration must not cancel a drag that starts in its callback")
        try expect(fixture.stopped.isEmpty, "Changed or unavailable enumeration must recheck drag state")
        fixture.duringSnapshot = nil
        fixture.drop()
        try expect(fixture.endCount == 1, "The drag must remain responsive after an interrupted refresh")
    }
}

private func testIdleRefreshAndCallbackGate() throws {
    let fixture = Fixture()
    defer { fixture.close() }
    fixture.manager.refreshDevices()
    try expect(fixture.started == [fixture.first] && fixture.stopped.isEmpty,
               "An unchanged idle snapshot must keep existing callbacks")
    fixture.nextDevices = [fixture.replacement]
    fixture.duringStart = { fixture.beginDrag() }
    fixture.manager.refreshDevices()
    try expect(fixture.events.isEmpty, "A startup callback must not begin a drag mid-refresh")
    try expect(fixture.stopped == [fixture.first] && fixture.started == [fixture.first, fixture.replacement],
               "Changed devices must restart while idle")
    fixture.duringStart = nil
    fixture.beginDrag()
    try expect(fixture.events.count == 1, "Touch recognition must resume after refreshing")
}

private func testExplicitLifecycleCancellationStillReleases() throws {
    for action in ["stop", "disable", "force"] {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.beginDrag()
        switch action {
        case "stop": fixture.manager.stop()
        case "disable": fixture.manager.setEnabled(false)
        default: fixture.manager.refreshDevices(force: true)
        }
        try expect(fixture.endCount == 1, "Explicit \(action) must release an active drag")
    }
}

private func testCompoundTapEndsCombinedModeThroughManager() throws {
    let fixture = Fixture(dragReleaseMode: .singleFingerTapOrCompoundTap)
    defer { fixture.close() }
    fixture.beginDrag()
    fixture.manager.processTouches([], timestamp: 1)
    fixture.manager.processTouches([threeTouches[0]], timestamp: 2)
    fixture.manager.processTouches([threeTouches[0], threeTouches[1]], timestamp: 2.1)
    fixture.manager.processTouches([threeTouches[0]], timestamp: 2.2)
    try expect(fixture.endCount == 1, "Compound tap must release a combined-mode drag once")
    try expect(fixture.events.count == 2, "Drop must not synthesize an extra click")
}

@main
private struct MultitouchManagerTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("refresh preserves a latched drag and resumes after drop", testRefreshPreservesLatchedDrag),
            ("enumeration failure during drag is deferred", testEnumerationFailureDuringDragIsDeferred),
            ("drag beginning during enumeration is preserved", testDragBeginningDuringEnumerationIsPreserved),
            ("idle refresh keeps or replaces callbacks safely", testIdleRefreshAndCallbackGate),
            ("explicit lifecycle cancellation still releases", testExplicitLifecycleCancellationStillReleases),
            ("compound tap releases combined mode once", testCompoundTapEndsCombinedModeThroughManager)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) device-refresh tests passed")
        if failures > 0 { exit(1) }
    }
}
