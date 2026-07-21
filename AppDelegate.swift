import Cocoa
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var multitouchManager: MultitouchManager?
    var isEnabled = true
    private var hasStartedMultitouch = false
    private var hasRequestedAccessibilityPrompt = false
    private var hasShownAccessibilityInstructions = false
    private var settings: MouseToucherSettings?
    private var settingsWindowController: SettingsWindowController?
    private let dragEventMonitor = DragEventMonitor()
    private let magnificationEmitter = NativeMagnificationEmitter()
    private var clickSequenceTracker = ClickSequenceTracker(
        doubleClickInterval: NSEvent.doubleClickInterval,
        maximumCursorMovement: 5.0
    )
    private var activeDrag: (button: CompoundTapButton, clickCount: Int64)?
    private var isMagnifying = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSettings()
        setupMenuBar()

        ensureAccessibilityAndStart()
    }

    @objc func showAccessibilityInstructions() {
        guard !hasShownAccessibilityInstructions else { return }
        hasShownAccessibilityInstructions = true
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MouseToucher 2.0 needs accessibility permissions to simulate clicks and native pinch gestures.\n\nPlease grant permission in:\nSystem Settings > Privacy & Security > Accessibility\n\nAfter enabling, return to MouseToucher 2.0. The app will begin working as soon as permission is granted."
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
        endActiveMagnification(at: CGEvent(source: nil)?.location ?? CGPoint.zero)
        dragEventMonitor.stop()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MouseToucher 2.0")
        }

        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Compound Tap: Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let accessibilityItem = NSMenuItem(title: "Accessibility Instructions…", action: #selector(showAccessibilityInstructions), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About MouseToucher 2.0", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let restartItem = NSMenuItem(title: "Restart MouseToucher 2.0", action: #selector(restart), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)
        menu.addItem(NSMenuItem(title: "Quit MouseToucher 2.0", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func showSettings() {
        settingsWindowController?.showWindow(nil)
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
        alert.messageText = "MouseToucher 2.0"
        alert.informativeText = """
        Intentional tap-to-click for Magic Mouse

        • Keep one finger still on the mouse
        • Tap the left side with another finger for left click
        • Tap the right side with another finger for right click
        • Repeat taps for double and multi-click
        • Pinch with two fingers for smooth native zoom
        • Place three fingers to drag immediately; lift all fingers to drop
        • Tune gesture recognition in Settings
        • Automatically use a preset for the current macOS version

        Version 2.0

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

    @objc func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert(error: error)
                    alert.messageText = "MouseToucher 2.0 Could Not Restart"
                    alert.runModal()
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
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

        let configuration = settings?.activeConfiguration ?? .default
        _ = dragEventMonitor.start()
        multitouchManager = MultitouchManager(configuration: configuration)
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
        multitouchManager?.onStatusChanged = { [weak self] status in
            let updateStatus: () -> Void = {
                let isTwoFingerGesture = status.touchCount >= 2 &&
                    (status.state == .tapping || status.state == .pinching)
                self?.dragEventMonitor.setScrollSuppressionEnabled(isTwoFingerGesture)
                self?.settingsWindowController?.updateStatus(status)
            }

            if Thread.isMainThread {
                updateStatus()
            } else {
                DispatchQueue.main.async(execute: updateStatus)
            }
        }
        multitouchManager?.start()
    }

    private func setupSettings() {
        let settings = MouseToucherSettings()
        self.settings = settings

        let controller = SettingsWindowController(
            settings: settings,
            launchAtLoginEnabled: isLaunchAtLoginEnabled,
            launchAtLoginAvailable: isLaunchAtLoginAvailable
        )
        controller.onActiveConfigurationChanged = { [weak self] configuration in
            self?.clickSequenceTracker.reset()
            self?.multitouchManager?.updateConfiguration(configuration)
        }
        controller.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled) ?? false
        }
        settingsWindowController = controller
    }

    private var isLaunchAtLoginAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    private var isLaunchAtLoginEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            if enabled, SMAppService.mainApp.status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "ログイン時の自動起動を許可してください"
                alert.informativeText = "システム設定の「一般 > ログイン項目」で MouseToucher 2.0 を許可してください。"
                alert.addButton(withTitle: "ログイン項目を開く")
                alert.addButton(withTitle: "後で")
                if alert.runModal() == .alertFirstButtonReturn {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "自動起動の設定を変更できませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
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
        case .magnify(let magnification):
            handleMagnification(magnification, at: location)
        }
    }

    private func handleMagnification(
        _ magnification: CompoundMagnification,
        at location: CGPoint
    ) {
        switch magnification.phase {
        case .began:
            guard !isMagnifying else { return }
            isMagnifying = true
            dragEventMonitor.beginPinch()
            magnificationEmitter.post(magnification, at: location)
        case .changed:
            guard isMagnifying else { return }
            magnificationEmitter.post(magnification, at: location)
        case .ended:
            guard isMagnifying else { return }
            magnificationEmitter.post(magnification, at: location)
            isMagnifying = false
            dragEventMonitor.endPinch()
        }
    }

    private func endActiveMagnification(at location: CGPoint) {
        guard isMagnifying else { return }
        magnificationEmitter.post(
            CompoundMagnification(phase: .ended, amount: 0),
            at: location
        )
        isMagnifying = false
        dragEventMonitor.endPinch()
    }

    private func beginDrag(at location: CGPoint, button: CompoundTapButton) {
        guard activeDrag == nil else { return }
        let clickCount = nextClickCount(button: button, location: location)
        activeDrag = (button: button, clickCount: clickCount)
        dragEventMonitor.begin(button: button, clickCount: clickCount)
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
        dragEventMonitor.end()
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
