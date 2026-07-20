import AppKit

final class SettingsWindowController: NSWindowController {
    var onActiveConfigurationChanged: ((CompoundGestureConfiguration) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Bool)?

    private let settings: MouseToucherSettings
    private var selectedPresetVersion: String

    private let presetPopup = NSPopUpButton()
    private let tapTimeSlider = NSSlider()
    private let movementSlider = NSSlider()
    private let splitSlider = NSSlider()
    private let tapTimeValueLabel = NSTextField(labelWithString: "")
    private let movementValueLabel = NSTextField(labelWithString: "")
    private let splitValueLabel = NSTextField(labelWithString: "")
    private let threeFingerDragCheckbox = NSButton()
    private let launchAtLoginCheckbox = NSButton()

    private let touchCountLabel = NSTextField(labelWithString: "0")
    private let gestureStateLabel = NSTextField(labelWithString: "待機中")
    private let recognizedGestureLabel = NSTextField(labelWithString: "なし")
    private let cancellationReasonLabel = NSTextField(labelWithString: "なし")

    init(
        settings: MouseToucherSettings,
        launchAtLoginEnabled: Bool,
        launchAtLoginAvailable: Bool
    ) {
        self.settings = settings
        selectedPresetVersion = settings.currentOSVersion
        super.init(window: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MouseToucher 1.8 設定"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        configureControls(
            launchAtLoginEnabled: launchAtLoginEnabled,
            launchAtLoginAvailable: launchAtLoginAvailable
        )
        buildLayout()
        refreshPresetPopup(selecting: selectedPresetVersion)
        loadSelectedPreset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func updateStatus(_ status: GestureStatusSnapshot) {
        touchCountLabel.stringValue = "\(status.touchCount)"
        gestureStateLabel.stringValue = status.state.displayName
        recognizedGestureLabel.stringValue = status.lastRecognizedGesture.displayName
        cancellationReasonLabel.stringValue = status.cancellationReason?.displayName ?? "なし"
    }

    func setLaunchAtLoginState(_ enabled: Bool) {
        launchAtLoginCheckbox.state = enabled ? .on : .off
    }

    private func configureControls(
        launchAtLoginEnabled: Bool,
        launchAtLoginAvailable: Bool
    ) {
        tapTimeSlider.minValue = 0.10
        tapTimeSlider.maxValue = 0.50
        tapTimeSlider.isContinuous = true
        tapTimeSlider.target = self
        tapTimeSlider.action = #selector(configurationControlChanged)

        movementSlider.minValue = 0.01
        movementSlider.maxValue = 0.12
        movementSlider.isContinuous = true
        movementSlider.target = self
        movementSlider.action = #selector(configurationControlChanged)

        splitSlider.minValue = 0.35
        splitSlider.maxValue = 0.75
        splitSlider.isContinuous = true
        splitSlider.target = self
        splitSlider.action = #selector(configurationControlChanged)

        for label in [tapTimeValueLabel, movementValueLabel, splitValueLabel] {
            label.alignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        threeFingerDragCheckbox.setButtonType(.switch)
        threeFingerDragCheckbox.title = "3本指ドラッグを有効にする"
        threeFingerDragCheckbox.target = self
        threeFingerDragCheckbox.action = #selector(configurationControlChanged)

        launchAtLoginCheckbox.setButtonType(.switch)
        launchAtLoginCheckbox.title = launchAtLoginAvailable
            ? "ログイン時に自動起動する"
            : "ログイン時に自動起動する（macOS 13以降）"
        launchAtLoginCheckbox.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginCheckbox.isEnabled = launchAtLoginAvailable
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        presetPopup.target = self
        presetPopup.action = #selector(presetSelectionChanged)

        cancellationReasonLabel.maximumNumberOfLines = 2
        cancellationReasonLabel.lineBreakMode = .byWordWrapping
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "ジェスチャー設定")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let osLabel = NSTextField(
            labelWithString: "現在の macOS: \(settings.currentOSVersion)（このプリセットを自動適用）"
        )
        osLabel.textColor = .secondaryLabelColor

        let presetButtons = NSStackView(views: [
            makeButton(title: "追加…", action: #selector(addPreset)),
            makeButton(title: "削除", action: #selector(removePreset)),
            makeButton(title: "既定にする", action: #selector(makeDefaultPreset)),
            makeButton(title: "現在のOSへ適用", action: #selector(applyPresetToCurrentOS))
        ])
        presetButtons.orientation = .horizontal
        presetButtons.spacing = 8

        let presetStack = NSStackView(views: [
            makeSectionTitle("OSバージョン別プリセット"),
            osLabel,
            presetPopup,
            presetButtons
        ])
        presetStack.orientation = .vertical
        presetStack.alignment = .leading
        presetStack.spacing = 8
        presetPopup.widthAnchor.constraint(equalToConstant: 330).isActive = true

        let settingsGrid = NSGridView(views: [
            [NSTextField(labelWithString: "タップ判定時間"), tapTimeSlider, tapTimeValueLabel],
            [NSTextField(labelWithString: "移動許容量"), movementSlider, movementValueLabel],
            [NSTextField(labelWithString: "左右クリック境界"), splitSlider, splitValueLabel]
        ])
        settingsGrid.rowSpacing = 12
        settingsGrid.columnSpacing = 12
        settingsGrid.column(at: 0).xPlacement = .leading
        settingsGrid.column(at: 1).width = 275
        settingsGrid.column(at: 2).width = 75

        let resetButton = makeButton(title: "選択中のプリセットを初期設定へ戻す", action: #selector(resetPreset))

        let behaviorStack = NSStackView(views: [
            makeSectionTitle("判定"),
            settingsGrid,
            threeFingerDragCheckbox,
            launchAtLoginCheckbox,
            resetButton
        ])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.spacing = 12

        let statusGrid = NSGridView(views: [
            [NSTextField(labelWithString: "接触指の数"), touchCountLabel],
            [NSTextField(labelWithString: "認識状態"), gestureStateLabel],
            [NSTextField(labelWithString: "最後に認識した操作"), recognizedGestureLabel],
            [NSTextField(labelWithString: "キャンセル理由"), cancellationReasonLabel]
        ])
        statusGrid.rowSpacing = 8
        statusGrid.columnSpacing = 18
        statusGrid.column(at: 0).xPlacement = .leading
        statusGrid.column(at: 0).width = 150
        statusGrid.column(at: 1).xPlacement = .leading

        let statusStack = NSStackView(views: [makeSectionTitle("現在の状態"), statusGrid])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 10

        let mainStack = NSStackView(views: [
            titleLabel,
            presetStack,
            separator(),
            behaviorStack,
            separator(),
            statusStack
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 15
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 572).isActive = true
        return box
    }

    private func refreshPresetPopup(selecting version: String) {
        presetPopup.removeAllItems()
        for presetVersion in settings.presetVersions {
            var suffixes: [String] = []
            if presetVersion == settings.currentOSVersion {
                suffixes.append("現在")
            }
            if presetVersion == settings.defaultPresetVersion {
                suffixes.append("既定")
            }
            let suffix = suffixes.isEmpty ? "" : "（\(suffixes.joined(separator: "・"))）"
            presetPopup.addItem(withTitle: "macOS \(presetVersion)\(suffix)")
            presetPopup.lastItem?.representedObject = presetVersion
        }

        if let item = presetPopup.itemArray.first(where: { ($0.representedObject as? String) == version }) {
            presetPopup.select(item)
            selectedPresetVersion = version
        } else if let firstVersion = presetPopup.selectedItem?.representedObject as? String {
            selectedPresetVersion = firstVersion
        }
    }

    private func loadSelectedPreset() {
        guard let configuration = settings.configuration(for: selectedPresetVersion) else { return }
        tapTimeSlider.doubleValue = configuration.tapTimeThreshold
        movementSlider.doubleValue = Double(configuration.movementThreshold)
        splitSlider.doubleValue = Double(configuration.rightClickSplit)
        threeFingerDragCheckbox.state = configuration.isThreeFingerDragEnabled ? .on : .off
        updateValueLabels()
    }

    private func configurationFromControls() -> CompoundGestureConfiguration {
        CompoundGestureConfiguration(
            tapTimeThreshold: tapTimeSlider.doubleValue,
            movementThreshold: CGFloat(movementSlider.doubleValue),
            rightClickSplit: CGFloat(splitSlider.doubleValue),
            isThreeFingerDragEnabled: threeFingerDragCheckbox.state == .on
        ).normalized
    }

    private func updateValueLabels() {
        tapTimeValueLabel.stringValue = String(format: "%.2f 秒", tapTimeSlider.doubleValue)
        movementValueLabel.stringValue = String(format: "%.3f", movementSlider.doubleValue)
        splitValueLabel.stringValue = String(format: "左 %.0f%%", splitSlider.doubleValue * 100)
    }

    @objc private func configurationControlChanged() {
        let configuration = configurationFromControls()
        updateValueLabels()
        if settings.updateConfiguration(configuration, for: selectedPresetVersion) {
            onActiveConfigurationChanged?(configuration)
        }
    }

    @objc private func launchAtLoginChanged() {
        let requested = launchAtLoginCheckbox.state == .on
        let accepted = onLaunchAtLoginChanged?(requested) ?? false
        if !accepted {
            launchAtLoginCheckbox.state = requested ? .off : .on
        }
    }

    @objc private func presetSelectionChanged() {
        guard let version = presetPopup.selectedItem?.representedObject as? String else { return }
        selectedPresetVersion = version
        loadSelectedPreset()
    }

    @objc private func addPreset() {
        let alert = NSAlert()
        alert.messageText = "OSバージョンのプリセットを追加"
        alert.informativeText = "例: 26.6 または 27.0.0。選択中の設定を複製します。"
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "macOSバージョン"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let version = MouseToucherSettings.normalizedVersion(input.stringValue)
        guard settings.addPreset(version: version, copying: selectedPresetVersion) else {
            showPresetError("空欄、または登録済みのバージョンです。")
            return
        }

        refreshPresetPopup(selecting: version)
        loadSelectedPreset()
    }

    @objc private func removePreset() {
        guard settings.removePreset(version: selectedPresetVersion) else {
            showPresetError("現在のOS用プリセットは削除できません。")
            return
        }
        refreshPresetPopup(selecting: settings.currentOSVersion)
        loadSelectedPreset()
    }

    @objc private func makeDefaultPreset() {
        guard settings.setDefaultPreset(version: selectedPresetVersion) else { return }
        refreshPresetPopup(selecting: selectedPresetVersion)
    }

    @objc private func applyPresetToCurrentOS() {
        guard let configuration = settings.applyPresetToCurrentOS(version: selectedPresetVersion) else { return }
        refreshPresetPopup(selecting: settings.currentOSVersion)
        loadSelectedPreset()
        onActiveConfigurationChanged?(configuration)
    }

    @objc private func resetPreset() {
        guard let configuration = settings.resetPreset(version: selectedPresetVersion) else { return }
        loadSelectedPreset()
        if selectedPresetVersion == settings.currentOSVersion {
            onActiveConfigurationChanged?(configuration)
        }
    }

    private func showPresetError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "プリセットを変更できません"
        alert.informativeText = message
        alert.runModal()
    }
}

private extension CompoundGestureState {
    var displayName: String {
        switch self {
        case .idle: return "待機中"
        case .anchorReady: return "固定指を認識"
        case .tapping: return "タップ判定中"
        case .dragging: return "ドラッグ中"
        case .waitingForRelease: return "全指が離れるのを待機"
        }
    }
}

private extension RecognizedGesture {
    var displayName: String {
        switch self {
        case .none: return "なし"
        case .leftClick: return "左クリック"
        case .rightClick: return "右クリック"
        case .dragStarted: return "ドラッグ開始"
        case .dropped: return "ドロップ"
        }
    }
}

private extension CompoundGestureCancellationReason {
    var displayName: String {
        switch self {
        case .anchorReleased: return "タップ中に固定指が離れました"
        case .anchorMoved: return "タップ中に固定指が動きました"
        case .tapMoved: return "タップする指の移動量が上限を超えました"
        case .tapTooLong: return "タップ時間が上限を超えました"
        case .replacementTouch: return "別の指に入れ替わりました"
        case .tooManyFingers: return "想定外の接触数です"
        case .threeFingerDragDisabled: return "3本指ドラッグが無効です"
        case .physicalButtonPressed: return "物理クリックを検出しました"
        case .disabled: return "MouseToucherが無効です"
        case .settingsChanged: return "設定変更のため判定をリセットしました"
        }
    }
}
