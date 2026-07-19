import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var multitouchManager: MultitouchManager?
    var isEnabled = true
    private var hasStartedMultitouch = false
    private var hasRequestedAccessibilityPrompt = false
    private var hasShownAccessibilityInstructions = false
    private var clickSequenceTracker = ClickSequenceTracker(
        doubleClickInterval: NSEvent.doubleClickInterval,
        maximumCursorMovement: 5.0
    )
    private var activeDrag: (button: CompoundTapButton, clickCount: Int64)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        ensureAccessibilityAndStart()
    }

    @objc func showAccessibilityInstructions() {
        guard !hasShownAccessibilityInstructions else { return }
        hasShownAccessibilityInstructions = true
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MouseToucher 1.4 needs accessibility permissions to simulate clicks.\n\nPlease grant permission in:\nSystem Settings > Privacy & Security > Accessibility\n\nAfter enabling, return to MouseToucher 1.4. The app will begin working as soon as permission is granted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else if response == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        multitouchManager?.stop()
        endActiveDrag(at: CGEvent(source: nil)?.location ?? CGPoint.zero)
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MouseToucher 1.4")
        }

        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Compound Tap: Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Accessibility Instructions…", action: #selector(showAccessibilityInstructions), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About MouseToucher 1.4", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MouseToucher 1.4", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleEnabled() {
        isEnabled.toggle()
        if let menu = statusItem?.menu,
           let item = menu.items.first {
            item.state = isEnabled ? .on : .off
            item.title = isEnabled ? "Compound Tap: Enabled" : "Compound Tap: Disabled"
        }
        multitouchManager?.setEnabled(isEnabled)
        if !isEnabled {
            clickSequenceTracker.reset()
        }
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MouseToucher 1.4"
        alert.informativeText = """
        Intentional tap-to-click for Magic Mouse

        • Keep one finger still on the mouse
        • Tap the left side with another finger for left click
        • Tap the right side with another finger for right click
        • Repeat taps for double and multi-click
        • Hold the second finger down, move the mouse, then lift to drag

        Version 1.4

        Uses private MultitouchSupport framework
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quit() {
        multitouchManager?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func ensureAccessibilityAndStart() {
        if AXIsProcessTrusted() {
            startMultitouchManager()
            return
        }

        requestAccessibilityPermissionIfNeeded()
        waitForAccessibilityPermission()
    }

    private func startMultitouchManager() {
        guard !hasStartedMultitouch else { return }
        hasStartedMultitouch = true

        multitouchManager = MultitouchManager()
        multitouchManager?.onGestureRecognized = { [weak self] location, event in
            let handleEvent: () -> Void = {
                self?.handleCompoundGesture(event, at: location)
            }

            if Thread.isMainThread {
                handleEvent()
            } else {
                DispatchQueue.main.async(execute: handleEvent)
            }
        }
        multitouchManager?.start()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !hasRequestedAccessibilityPrompt else { return }
        hasRequestedAccessibilityPrompt = true

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func waitForAccessibilityPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            if AXIsProcessTrusted() {
                self.startMultitouchManager()
            } else {
                self.waitForAccessibilityPermission()
            }
        }
    }

    func synthesizeClick(at location: CGPoint, button: CompoundTapButton) {
        let clickCount = nextClickCount(
            button: button,
            location: location
        )

        postMouseEvent(isDown: true, at: location, button: button, clickCount: clickCount)
        postMouseEvent(isDown: false, at: location, button: button, clickCount: clickCount)
    }

    private func handleCompoundGesture(_ event: CompoundGestureEvent, at location: CGPoint) {
        switch event {
        case .click(let tap):
            synthesizeClick(at: location, button: tap.button)
        case .dragBegan(let tap):
            beginDrag(at: location, button: tap.button)
        case .dragEnded(let button):
            endActiveDrag(at: location, expectedButton: button)
        }
    }

    private func beginDrag(at location: CGPoint, button: CompoundTapButton) {
        guard activeDrag == nil else { return }
        let clickCount = nextClickCount(button: button, location: location)
        activeDrag = (button: button, clickCount: clickCount)
        postMouseEvent(isDown: true, at: location, button: button, clickCount: clickCount)
    }

    private func endActiveDrag(at location: CGPoint, expectedButton: CompoundTapButton? = nil) {
        guard let activeDrag,
              expectedButton == nil || expectedButton == activeDrag.button else {
            return
        }

        postMouseEvent(
            isDown: false,
            at: location,
            button: activeDrag.button,
            clickCount: activeDrag.clickCount
        )
        self.activeDrag = nil
    }

    private func nextClickCount(button: CompoundTapButton, location: CGPoint) -> Int64 {
        clickSequenceTracker.nextClickCount(
            button: button,
            location: location,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private func postMouseEvent(
        isDown: Bool,
        at location: CGPoint,
        button: CompoundTapButton,
        clickCount: Int64
    ) {
        let mouseButton: CGMouseButton = button == .right ? .right : .left
        let eventType: CGEventType
        if button == .right {
            eventType = isDown ? .rightMouseDown : .rightMouseUp
        } else {
            eventType = isDown ? .leftMouseDown : .leftMouseUp
        }

        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) {
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
            event.post(tap: .cghidEventTap)
        }
    }
}
