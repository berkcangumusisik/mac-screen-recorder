import AppKit
import ServiceManagement

/// Single source of truth for user preferences.
///
/// Preferences are persisted as one JSON blob so adding a field never needs a
/// migration; unknown fields simply fall back to their default value.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let storageKey = "app.snaplet.preferences"

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persist()
            if preferences.appearance != oldValue.appearance {
                applyAppearance()
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = Preferences()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func resetToDefaults() {
        preferences = Preferences()
    }

    func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Makes sure the output directory exists, falling back to the default
    /// location if the configured one cannot be created.
    @discardableResult
    func ensureOutputDirectory() -> URL {
        let target = preferences.outputDirectory
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return target
        } catch {
            Log.app.error("Output directory unavailable, falling back to default: \(error.localizedDescription, privacy: .public)")
            let fallback = Preferences.defaultOutputDirectory
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            if preferences.outputDirectoryPath != nil {
                preferences.outputDirectoryPath = nil
            }
            return fallback
        }
    }

    // MARK: - Login item

    /// Uses `SMAppService`, the supported API on macOS 13+.
    func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if preferences.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var launchAtLoginIsEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
