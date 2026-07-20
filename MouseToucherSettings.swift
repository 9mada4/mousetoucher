import Foundation

struct OSGesturePreset: Codable, Equatable {
    var osVersion: String
    var tapTimeThreshold: Double
    var movementThreshold: Double
    var rightClickSplit: Double
    var isThreeFingerDragEnabled: Bool

    init(osVersion: String, configuration: CompoundGestureConfiguration) {
        self.osVersion = osVersion
        tapTimeThreshold = configuration.tapTimeThreshold
        movementThreshold = Double(configuration.movementThreshold)
        rightClickSplit = Double(configuration.rightClickSplit)
        isThreeFingerDragEnabled = configuration.isThreeFingerDragEnabled
    }

    var configuration: CompoundGestureConfiguration {
        CompoundGestureConfiguration(
            tapTimeThreshold: tapTimeThreshold,
            movementThreshold: CGFloat(movementThreshold),
            rightClickSplit: CGFloat(rightClickSplit),
            isThreeFingerDragEnabled: isThreeFingerDragEnabled
        ).normalized
    }
}

/// Stores gesture presets in a stable preference domain so settings survive
/// the version-specific bundle identifier used by distributed builds.
final class MouseToucherSettings {
    static let preferenceSuiteName = "com.mousetoucher.shared-settings"

    private enum Key {
        static let presets = "osGesturePresets"
        static let defaultPresetVersion = "defaultPresetVersion"
    }

    let currentOSVersion: String

    private let defaults: UserDefaults
    private var presetsByVersion: [String: OSGesturePreset] = [:]

    private(set) var defaultPresetVersion: String

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: preferenceSuiteName),
        currentOSVersion: String = MouseToucherSettings.systemOSVersion
    ) {
        self.defaults = defaults ?? .standard
        self.currentOSVersion = currentOSVersion

        if let data = self.defaults.data(forKey: Key.presets),
           let presets = try? JSONDecoder().decode([OSGesturePreset].self, from: data) {
            presetsByVersion = Dictionary(
                presets.map { ($0.osVersion, $0) },
                uniquingKeysWith: { _, newest in newest }
            )
        }

        let savedDefault = self.defaults.string(forKey: Key.defaultPresetVersion)
        defaultPresetVersion = savedDefault ?? currentOSVersion

        if presetsByVersion.isEmpty {
            presetsByVersion[currentOSVersion] = OSGesturePreset(
                osVersion: currentOSVersion,
                configuration: .default
            )
            defaultPresetVersion = currentOSVersion
        } else if presetsByVersion[defaultPresetVersion] == nil {
            defaultPresetVersion = presetsByVersion.keys.sorted(by: Self.versionSort).first ?? currentOSVersion
        }

        // Every exact system version gets its own editable preset. On the first
        // launch after an OS update or downgrade, start from the chosen default.
        if presetsByVersion[currentOSVersion] == nil {
            let fallback = presetsByVersion[defaultPresetVersion]?.configuration ?? .default
            presetsByVersion[currentOSVersion] = OSGesturePreset(
                osVersion: currentOSVersion,
                configuration: fallback
            )
        }

        save()
    }

    static var systemOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var activeConfiguration: CompoundGestureConfiguration {
        configuration(for: currentOSVersion) ?? .default
    }

    var presetVersions: [String] {
        presetsByVersion.keys.sorted(by: Self.versionSort)
    }

    func configuration(for version: String) -> CompoundGestureConfiguration? {
        presetsByVersion[version]?.configuration
    }

    @discardableResult
    func updateConfiguration(
        _ configuration: CompoundGestureConfiguration,
        for version: String
    ) -> Bool {
        guard presetsByVersion[version] != nil else { return false }
        presetsByVersion[version] = OSGesturePreset(
            osVersion: version,
            configuration: configuration.normalized
        )
        save()
        return version == currentOSVersion
    }

    @discardableResult
    func addPreset(version rawVersion: String, copying sourceVersion: String) -> Bool {
        let version = Self.normalizedVersion(rawVersion)
        guard !version.isEmpty, presetsByVersion[version] == nil else { return false }

        let configuration = configuration(for: sourceVersion) ?? activeConfiguration
        presetsByVersion[version] = OSGesturePreset(
            osVersion: version,
            configuration: configuration
        )
        save()
        return true
    }

    @discardableResult
    func removePreset(version: String) -> Bool {
        guard version != currentOSVersion,
              presetsByVersion.count > 1,
              presetsByVersion.removeValue(forKey: version) != nil else {
            return false
        }

        if defaultPresetVersion == version {
            defaultPresetVersion = currentOSVersion
        }
        save()
        return true
    }

    @discardableResult
    func setDefaultPreset(version: String) -> Bool {
        guard presetsByVersion[version] != nil else { return false }
        defaultPresetVersion = version
        save()
        return true
    }

    func applyPresetToCurrentOS(version: String) -> CompoundGestureConfiguration? {
        guard let configuration = configuration(for: version) else { return nil }
        _ = updateConfiguration(configuration, for: currentOSVersion)
        return configuration
    }

    func resetPreset(version: String) -> CompoundGestureConfiguration? {
        guard presetsByVersion[version] != nil else { return nil }
        let configuration = CompoundGestureConfiguration.default
        _ = updateConfiguration(configuration, for: version)
        return configuration
    }

    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let presets = presetVersions.compactMap { presetsByVersion[$0] }
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Key.presets)
        }
        defaults.set(defaultPresetVersion, forKey: Key.defaultPresetVersion)
    }

    private static func versionSort(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }
}
