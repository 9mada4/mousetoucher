import AppKit
import ApplicationServices

/// Conservative title-bar hit testing: never reinterpret a button, tab, text
/// field, document, or scroll area as a request to move the entire window.
enum WindowDragGeometry {
    static func isTitleBarHit(cursor: CGPoint, frame: CGRect, closeButtonFrame: CGRect?, roles: [String]) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.contains(cursor),
              !roles.isEmpty,
              roles.allSatisfy({ ["AXWindow", "AXGroup", "AXToolbar", "AXStaticText"].contains($0) }) else {
            return false
        }
        let titleBarHeight = closeButtonFrame.map { min(64, max(28, 2 * ($0.midY - frame.minY))) } ?? 28
        return cursor.y < frame.minY + titleBarHeight
    }

    static func position(windowOrigin: CGPoint, initialCursor: CGPoint, cursor: CGPoint) -> CGPoint {
        CGPoint(x: windowOrigin.x + cursor.x - initialCursor.x,
                y: windowOrigin.y + cursor.y - initialCursor.y)
    }
}

protocol WindowDragTarget: AnyObject {
    var origin: CGPoint { get }
    func move(to point: CGPoint) -> Bool
}

/// Owns exactly one window for one gesture. Absolute displacement avoids drift
/// and remains correct on monitors with negative screen coordinates.
final class WindowDragSession {
    private var target: WindowDragTarget?
    private var initialCursor = CGPoint.zero
    private var initialOrigin = CGPoint.zero
    private var previousCursor = CGPoint.zero
    var isActive: Bool { target != nil }

    func begin(target: WindowDragTarget, cursor: CGPoint) {
        self.target = target
        initialOrigin = target.origin
        initialCursor = cursor
        previousCursor = cursor
    }

    @discardableResult
    func update(cursor: CGPoint) -> Bool {
        guard let target else { return false }
        guard cursor != previousCursor else { return true }
        let point = WindowDragGeometry.position(windowOrigin: initialOrigin, initialCursor: initialCursor, cursor: cursor)
        guard point.x.isFinite, point.y.isFinite, target.move(to: point) else {
            end()
            return false
        }
        previousCursor = cursor
        return true
    }

    func end() { target = nil }
}

private final class AccessibilityWindowDragTarget: WindowDragTarget {
    let window: AXUIElement
    let origin: CGPoint

    init(window: AXUIElement, origin: CGPoint) {
        self.window = window
        self.origin = origin
    }

    func move(to point: CGPoint) -> Bool {
        var position = point
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }
}

private final class LocalWindowDragTarget: WindowDragTarget {
    let window: NSWindow
    let origin: CGPoint
    let screenHeight: CGFloat

    init(window: NSWindow, screenHeight: CGFloat) {
        self.window = window
        self.screenHeight = screenHeight
        origin = CGPoint(x: window.frame.minX, y: screenHeight - window.frame.maxY)
    }

    func move(to point: CGPoint) -> Bool {
        guard window.isVisible else { return false }
        window.setFrameOrigin(CGPoint(x: point.x, y: screenHeight - point.y - window.frame.height))
        return true
    }
}

/// macOS 27 can deliver synthesized drags to document content without moving
/// the containing window. For title bars, use the existing Accessibility grant
/// to set AXPosition instead of sending a synthetic held mouse button.
final class WindowDragController {
    private let session = WindowDragSession()
    private var timer: Timer?
    var onFailure: (() -> Void)?

    func begin(at cursor: CGPoint) -> Bool {
        end()
        // AX messaging back into our own main thread can time out. Use AppKit
        // for our own standard title bar, after checking the topmost window.
        if let local = localTarget(at: cursor) {
            local.window.orderFront(nil)
            start(target: local, cursor: cursor)
            return true
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(cursor.x), Float(cursor.y), &hit) == .success,
              let hit else { return false }
        AXUIElementSetMessagingTimeout(hit, 0.1)
        let window = stringAttribute(hit, kAXRoleAttribute) == kAXWindowRole
            ? hit : elementAttribute(hit, kAXWindowAttribute)
        guard let window else { return false }
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard stringAttribute(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              (attribute(window, "AXFullScreen") as? Bool) != true,
              let frame = frame(of: window) else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        var roles: [String] = []
        var current = hit
        var reachedWindow = false
        for _ in 0..<12 {
            guard let role = stringAttribute(current, kAXRoleAttribute) else { return false }
            roles.append(role)
            if CFEqual(current, window) { reachedWindow = true; break }
            guard let parent = elementAttribute(current, kAXParentAttribute) else { return false }
            current = parent
        }
        let closeFrame = elementAttribute(window, kAXCloseButtonAttribute).flatMap { self.frame(of: $0) }
        guard reachedWindow,
              WindowDragGeometry.isTitleBarHit(cursor: cursor, frame: frame, closeButtonFrame: closeFrame, roles: roles) else {
            return false
        }

        let target = AccessibilityWindowDragTarget(window: window, origin: frame.origin)
        // Check that this particular app accepts position writes before taking
        // over the gesture. A failure leaves ordinary drag processing intact.
        guard target.move(to: frame.origin) else { return false }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        start(target: target, cursor: cursor)
        return true
    }

    private func start(target: WindowDragTarget, cursor: CGPoint) {
        session.begin(target: target, cursor: cursor)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func localTarget(at cursor: CGPoint) -> LocalWindowDragTarget? {
        guard let screenHeight = NSScreen.screens.first?.frame.height else { return nil }
        let point = CGPoint(x: cursor.x, y: screenHeight - cursor.y)
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard let window = NSApp.windows.first(where: { $0.windowNumber == number }),
              window.isVisible, window.isMovable, window.styleMask.contains(.titled),
              !window.styleMask.contains(.fullScreen),
              !window.styleMask.contains(.fullSizeContentView),
              let content = window.contentView else { return nil }
        let contentFrame = window.convertToScreen(content.convert(content.bounds, to: nil))
        guard point.y >= contentFrame.maxY, window.frame.contains(point) else { return nil }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] {
            if let button = window.standardWindowButton(kind), !button.isHidden,
               window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) {
                return nil
            }
        }
        return LocalWindowDragTarget(window: window, screenHeight: screenHeight)
    }

    func end() {
        timer?.invalidate()
        timer = nil
        session.end()
    }

    private func update() {
        // Do not compete with a real mouse press, for example on a close button.
        if CGEventSource.buttonState(.hidSystemState, button: .left) ||
            CGEventSource.buttonState(.hidSystemState, button: .right) {
            end()
            return
        }
        guard let cursor = CGEvent(source: nil)?.location else { return }
        if !session.update(cursor: cursor) {
            end()
            onFailure?()
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    deinit { end() }
}
