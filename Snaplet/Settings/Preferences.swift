import Foundation

enum ImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var displayName: String { self == .png ? "PNG" : "JPEG" }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}

enum LanguagePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, english, turkish
    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .turkish: return "tr"
        }
    }
}

enum ResolutionCap: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, p1080, p1440, p2160

    var id: String { rawValue }

    /// Longest-edge limit in pixels, or `nil` for "do not downscale".
    var longestEdge: Int? {
        switch self {
        case .original: return nil
        case .p1080: return 1920
        case .p1440: return 2560
        case .p2160: return 3840
        }
    }

    var displayName: String {
        switch self {
        case .original: return String(localized: "Original")
        case .p1080: return "1080p"
        case .p1440: return "1440p"
        case .p2160: return "4K"
        }
    }
}

enum WebcamShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle, roundedRectangle
    var id: String { rawValue }
    var displayName: String {
        self == .circle ? String(localized: "Circle") : String(localized: "Rounded rectangle")
    }
}

enum OverlayCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .topLeading: return String(localized: "Top left")
        case .topTrailing: return String(localized: "Top right")
        case .bottomLeading: return String(localized: "Bottom left")
        case .bottomTrailing: return String(localized: "Bottom right")
        }
    }
}

/// Everything the user can configure, in one Codable blob stored in
/// `UserDefaults`. Media never goes in here — only preferences.
struct Preferences: Codable, Equatable, Sendable {
    // Capture
    var copyImageToClipboard = true
    var autoSaveToDisk = true
    var outputDirectoryPath: String?
    var imageFormat: ImageFormat = .png
    var jpegQuality: Double = 0.9
    var showPreviewPanel = true
    var playCaptureSound = true

    // Appearance
    var appearance: AppearancePreference = .system
    var language: LanguagePreference = .system
    var defaultStylePresetID: String = "clean"

    // Recording
    var videoFrameRate: Int = 60
    var resolutionCap: ResolutionCap = .original
    var recordMicrophone = false
    var recordSystemAudio = true
    var showCursorInRecording = true
    var highlightMouseClicks = false
    var countdownSeconds: Int = 3
    var webcamEnabled = false
    var webcamDeviceID: String?
    var webcamShape: WebcamShape = .circle
    var webcamCorner: OverlayCorner = .bottomTrailing
    var webcamSizePercent: Double = 0.22

    // Library
    var historyEnabled = true

    // System
    var launchAtLogin = false

    /// Shortcut bindings keyed by `HotkeyAction.rawValue`. A missing key means
    /// "use the default"; an explicit `nil` means the user unbound it.
    var shortcuts: [String: KeyboardShortcut?] = [:]

    func shortcut(for action: HotkeyAction) -> KeyboardShortcut? {
        if let stored = shortcuts[action.rawValue] { return stored }
        return action.defaultShortcut
    }

    var resolvedShortcuts: [HotkeyAction: KeyboardShortcut?] {
        var result: [HotkeyAction: KeyboardShortcut?] = [:]
        for action in HotkeyAction.allCases {
            result[action] = shortcut(for: action)
        }
        return result
    }

    static let defaultOutputDirectory: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Snaplet", isDirectory: true)
    }()

    var outputDirectory: URL {
        if let path = outputDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultOutputDirectory
    }
}
