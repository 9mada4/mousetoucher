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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        ensureAccessibilityAndStart()
    }

    @objc func showAccessibilityInstructions() {
        guard !hasShownAccessibilityInstructions else { return }
        hasShownAccessibilityInstructions = true
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Mouse Toucher needs accessibility permissions to simulate clicks.\n\nPlease grant permission in:\nSystem Settings > Privacy & Security > Accessibility\n\nAfter enabling, return to Mouse Toucher. The app will begin working as soon as permission is granted."
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
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Mouse Toucher")
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
        menu.addItem(NSMenuItem(title: "About Mouse Toucher", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Mouse Toucher", action: #selector(quit), keyEquivalent: "q"))

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
        alert.messageText = "Mouse Toucher"
        alert.informativeText = """
        Intentional tap-to-click for Magic Mouse

        • Keep one finger still on the mouse
        • Tap the left side with another finger for left click
        • Tap the right side with another finger for right click
        • Repeat taps for double and multi-click

        Version 1.2

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
        multitouchManager?.onClickSynthesized = { [weak self] location, button in
            DispatchQueue.main.async {
                self?.synthesizeClick(at: location, button: button)
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
        let timestamp = ProcessInfo.processInfo.systemUptime
        let clickCount = clickSequenceTracker.nextClickCount(
            button: button,
            location: location,
            timestamp: timestamp
        )

        let mouseButton: CGMouseButton = button == .right ? .right : .left
        let mouseDownType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let mouseUpType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp

        if let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseDownType,
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) {
            mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
            mouseDown.post(tap: .cghidEventTap)
        }

        if let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseUpType,
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) {
            mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
            mouseUp.post(tap: .cghidEventTap)
        }
    }
}
