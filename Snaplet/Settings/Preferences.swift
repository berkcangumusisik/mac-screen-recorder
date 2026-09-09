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
///
/// Decoding is written by hand rather than synthesised. The synthesised version
/// throws `keyNotFound` for any key the stored blob does not contain, so adding
/// a single new preference would have thrown away every existing setting the
/// next time Snaplet started. Each field falls back to its default instead.
struct Preferences: Codable, Equatable, Sendable {
    // Capture
    var copyImageToClipboard = true
    var autoSaveToDisk = true
    var outputDirectoryPath: String?
    var imageFormat: ImageFormat = .png
    var jpegQuality: Double = 0.9
    var showPreviewPanel = true
    var playCaptureSound = true
    /// Seconds to wait after choosing what to capture, so menus and hover states
    /// can be opened first. 0 captures immediately.
    var captureDelaySeconds = 0

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

extension Preferences {

    enum CodingKeys: String, CodingKey {
        case copyImageToClipboard
        case autoSaveToDisk
        case imageFormat
        case jpegQuality
        case showPreviewPanel
        case playCaptureSound
        case captureDelaySeconds
        case appearance
        case language
        case defaultStylePresetID
        case videoFrameRate
        case resolutionCap
        case recordMicrophone
        case recordSystemAudio
        case showCursorInRecording
        case highlightMouseClicks
        case countdownSeconds
        case webcamEnabled
        case webcamShape
        case webcamCorner
        case webcamSizePercent
        case historyEnabled
        case launchAtLogin
        case outputDirectoryPath
        case webcamDeviceID
        case shortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        self.init()

        copyImageToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyImageToClipboard)
            ?? defaults.copyImageToClipboard
        autoSaveToDisk = try container.decodeIfPresent(Bool.self, forKey: .autoSaveToDisk)
            ?? defaults.autoSaveToDisk
        imageFormat = try container.decodeIfPresent(ImageFormat.self, forKey: .imageFormat)
            ?? defaults.imageFormat
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality)
            ?? defaults.jpegQuality
        showPreviewPanel = try container.decodeIfPresent(Bool.self, forKey: .showPreviewPanel)
            ?? defaults.showPreviewPanel
        playCaptureSound = try container.decodeIfPresent(Bool.self, forKey: .playCaptureSound)
            ?? defaults.playCaptureSound
        captureDelaySeconds = try container.decodeIfPresent(Int.self, forKey: .captureDelaySeconds)
            ?? defaults.captureDelaySeconds
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance)
            ?? defaults.appearance
        language = try container.decodeIfPresent(LanguagePreference.self, forKey: .language)
            ?? defaults.language
        defaultStylePresetID = try container.decodeIfPresent(String.self, forKey: .defaultStylePresetID)
            ?? defaults.defaultStylePresetID
        videoFrameRate = try container.decodeIfPresent(Int.self, forKey: .videoFrameRate)
            ?? defaults.videoFrameRate
        resolutionCap = try container.decodeIfPresent(ResolutionCap.self, forKey: .resolutionCap)
            ?? defaults.resolutionCap
        recordMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophone)
            ?? defaults.recordMicrophone
        recordSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio)
            ?? defaults.recordSystemAudio
        showCursorInRecording = try container.decodeIfPresent(Bool.self, forKey: .showCursorInRecording)
            ?? defaults.showCursorInRecording
        highlightMouseClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightMouseClicks)
            ?? defaults.highlightMouseClicks
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds)
            ?? defaults.countdownSeconds
        webcamEnabled = try container.decodeIfPresent(Bool.self, forKey: .webcamEnabled)
            ?? defaults.webcamEnabled
        webcamShape = try container.decodeIfPresent(WebcamShape.self, forKey: .webcamShape)
            ?? defaults.webcamShape
        webcamCorner = try container.decodeIfPresent(OverlayCorner.self, forKey: .webcamCorner)
            ?? defaults.webcamCorner
        webcamSizePercent = try container.decodeIfPresent(Double.self, forKey: .webcamSizePercent)
            ?? defaults.webcamSizePercent
        historyEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyEnabled)
            ?? defaults.historyEnabled
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? defaults.launchAtLogin
        outputDirectoryPath = try container.decodeIfPresent(String.self, forKey: .outputDirectoryPath)
        webcamDeviceID = try container.decodeIfPresent(String.self, forKey: .webcamDeviceID)
        shortcuts = try container.decodeIfPresent([String: KeyboardShortcut?].self,
                                                 forKey: .shortcuts) ?? defaults.shortcuts
    }
}
