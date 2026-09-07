import AppKit
import SwiftUI

struct SettingsView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case general, shortcuts, image, recording, library, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .shortcuts: return String(localized: "Shortcuts")
            case .image: return String(localized: "Image")
            case .recording: return String(localized: "Recording")
            case .library: return String(localized: "Library")
            case .about: return String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .shortcuts: return "keyboard"
            case .image: return "photo"
            case .recording: return "video"
            case .library: return "clock.arrow.circlepath"
            case .about: return "info.circle"
            }
        }
    }

    let environment: AppEnvironment
    @State private var selection: Tab = .general

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: 560, height: 520)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .general: GeneralSettingsView(environment: environment)
        case .shortcuts: ShortcutSettingsView(environment: environment)
        case .image: ImageSettingsView()
        case .recording: RecordingSettingsView(environment: environment)
        case .library: LibrarySettingsView(environment: environment)
        case .about: AboutSettingsView()
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    let environment: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Copy captures to the clipboard"),
                       isOn: $settings.preferences.copyImageToClipboard)
                Toggle(String(localized: "Save captures to a folder automatically"),
                       isOn: $settings.preferences.autoSaveToDisk)
                Toggle(String(localized: "Show the preview panel after a capture"),
                       isOn: $settings.preferences.showPreviewPanel)
                Toggle(String(localized: "Play a sound when a capture succeeds"),
                       isOn: $settings.preferences.playCaptureSound)
            }

            Section(String(localized: "Output folder")) {
                HStack {
                    Text(settings.preferences.outputDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Choose…"), action: chooseFolder)
                    Button(String(localized: "Reveal")) {
                        NSWorkspace.shared.open(settings.ensureOutputDirectory())
                    }
                }
            }

            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Theme"), selection: $settings.preferences.appearance) {
                    Text(String(localized: "Match system")).tag(AppearancePreference.system)
                    Text(String(localized: "Light")).tag(AppearancePreference.light)
                    Text(String(localized: "Dark")).tag(AppearancePreference.dark)
                }
                Picker(String(localized: "Language"), selection: $settings.preferences.language) {
                    Text(String(localized: "Match system")).tag(LanguagePreference.system)
                    Text("English").tag(LanguagePreference.english)
                    Text("Türkçe").tag(LanguagePreference.turkish)
                }
                Text(String(localized: "Language changes take effect the next time Snaplet starts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "System")) {
                Toggle(String(localized: "Open Snaplet at login"), isOn: $settings.preferences.launchAtLogin)
                    .onChange(of: settings.preferences.launchAtLogin) { _, _ in
                        settings.syncLaunchAtLogin()
                    }
                PermissionRow(title: String(localized: "Screen & System Audio Recording"),
                              status: settings.permissionsScreen,
                              pane: .screenRecording)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.preferences.language) { _, newValue in
            LanguageOverride.apply(newValue)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.preferences.outputDirectory
        panel.prompt = String(localized: "Use Folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.preferences.outputDirectoryPath = url.path
    }
}

struct PermissionRow: View {
    let title: String
    let status: PermissionsService.Status
    let pane: PermissionsService.Pane

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(status.isAuthorized ? String(localized: "Granted") : String(localized: "Not granted"),
                  systemImage: status.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isAuthorized ? Color.green : Color.orange)
                .labelStyle(.titleAndIcon)
            if !status.isAuthorized {
                Button(String(localized: "Open…")) {
                    PermissionsService.shared.openSystemSettings(pane)
                }
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    let environment: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(action.title, systemImage: action.symbolName)
                            Spacer()
                            ShortcutRecorder(shortcut: binding(for: action),
                                             accessibilityLabel: action.title)
                                .frame(width: 130, height: 24)
                        }
                        if let failure = environment.hotkeyFailures[action] {
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Global shortcuts"))
            } footer: {
                Text(String(localized: "Press ⌫ while recording to unbind a shortcut. Snaplet's defaults use ⌃⌥⌘ so they do not collide with the built-in macOS screenshot shortcuts."))
                    .font(.caption)
            }

            Section {
                Button(String(localized: "Restore default shortcuts")) {
                    settings.preferences.shortcuts = [:]
                    environment.reloadHotkeys()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for action: HotkeyAction) -> Binding<KeyboardShortcut?> {
        Binding(
            get: { settings.preferences.shortcut(for: action) },
            set: { newValue in
                settings.preferences.shortcuts[action.rawValue] = .some(newValue)
                environment.reloadHotkeys()
            }
        )
    }
}

// MARK: - Image

struct ImageSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section(String(localized: "Screenshot output")) {
                Picker(String(localized: "Format"), selection: $settings.preferences.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                if settings.preferences.imageFormat == .jpeg {
                    VStack(alignment: .leading) {
                        Slider(value: $settings.preferences.jpegQuality, in: 0.3...1.0) {
                            Text(String(localized: "JPEG quality"))
                        }
                        Text("\(Int(settings.preferences.jpegQuality * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Picker(String(localized: "Default presentation style"),
                       selection: $settings.preferences.defaultStylePresetID) {
                    ForEach(StylePreset.builtIn) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            } header: {
                Text(String(localized: "Share-ready styling"))
            } footer: {
                Text(String(localized: "Applied when you open the Style tab in the editor. Nothing is added to a plain capture."))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Snaplet").font(.title.weight(.semibold))
            Text(String(localized: "Capture instantly. Explain clearly. Share beautifully."))
                .foregroundStyle(.secondary)
            Text(String(localized: "Version \(version)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().padding(.horizontal, 60)
            Text(String(localized: "Captures, edits, OCR and exports all happen on this Mac. Snaplet has no account, no telemetry and makes no network requests."))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            Text(String(localized: "MIT licensed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Applies the language override used by the next launch.
enum LanguageOverride {
    static func apply(_ preference: LanguagePreference) {
        let defaults = UserDefaults.standard
        if let identifier = preference.localeIdentifier {
            defaults.set([identifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}

extension SettingsStore {
    var permissionsScreen: PermissionsService.Status {
        PermissionsService.shared.screenRecording
    }
}
