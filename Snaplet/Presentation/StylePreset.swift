import AppKit
import SwiftUI

/// A colour that survives a round-trip through JSON.
struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(converted.redComponent),
                  green: Double(converted.greenComponent),
                  blue: Double(converted.blueComponent),
                  alpha: Double(converted.alphaComponent))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor { nsColor.cgColor }
    var swiftUIColor: Color { Color(nsColor) }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

enum BackgroundStyle: Codable, Equatable, Hashable, Sendable {
    case transparent
    case solid(RGBAColor)
    /// `angle` is in degrees, 0 = left-to-right, 90 = bottom-to-top.
    case gradient(start: RGBAColor, end: RGBAColor, angle: Double)
    /// A user-chosen image file. Stored as a path so presets stay portable.
    case image(path: String)
}

enum AspectPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, square, wide, vertical, classic

    var id: String { rawValue }

    /// width / height, or `nil` to keep the source aspect ratio.
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .vertical: return 9.0 / 16.0
        case .classic: return 4.0 / 3.0
        }
    }

    var displayName: String {
        switch self {
        case .original: return String(localized: "Original")
        case .square: return "1:1"
        case .wide: return "16:9"
        case .vertical: return "9:16"
        case .classic: return "4:3"
        }
    }
}

struct ShadowStyle: Codable, Equatable, Hashable, Sendable {
    var radius: Double
    var opacity: Double
    var offsetY: Double

    static let none = ShadowStyle(radius: 0, opacity: 0, offsetY: 0)
    static let soft = ShadowStyle(radius: 28, opacity: 0.22, offsetY: 12)
    static let deep = ShadowStyle(radius: 44, opacity: 0.42, offsetY: 18)
}

/// The share-ready presentation applied around a screenshot or video frame.
struct StylePreset: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var background: BackgroundStyle
    /// Padding as a fraction of the content's longest edge, so presets look the
    /// same on a small crop and on a 4K screenshot.
    var paddingFraction: Double
    var cornerRadius: Double
    var shadow: ShadowStyle
    var showsWindowFrame: Bool
    var aspect: AspectPreset
    var title: String
    var subtitle: String
    var textColor: RGBAColor
    var isBuiltIn: Bool

    static let builtIn: [StylePreset] = [clean, midnight, studio, docs, social]

    static func preset(withID id: String) -> StylePreset {
        builtIn.first { $0.id == id } ?? clean
    }

    static let clean = StylePreset(
        id: "clean",
        name: String(localized: "Clean"),
        background: .solid(RGBAColor(red: 0.96, green: 0.96, blue: 0.97)),
        paddingFraction: 0.06,
        cornerRadius: 12,
        shadow: .soft,
        showsWindowFrame: false,
        aspect: .original,
        title: "",
        subtitle: "",
        textColor: RGBAColor(red: 0.11, green: 0.12, blue: 0.14),
        isBuiltIn: true)

    static let midnight = StylePreset(
        id: "midnight",
        name: String(localized: "Midnight"),
        background: .solid(RGBAColor(red: 0.07, green: 0.08, blue: 0.11)),
        paddingFraction: 0.07,
        cornerRadius: 14,
        shadow: .deep,
        showsWindowFrame: true,
        aspect: .original,
        title: "",
        subtitle: "",
        textColor: RGBAColor(red: 0.92, green: 0.93, blue: 0.96),
        isBuiltIn: true)

    static let studio = StylePreset(
        id: "studio",
        name: String(localized: "Studio"),
        background: .gradient(start: RGBAColor(red: 0.36, green: 0.42, blue: 0.86),
                              end: RGBAColor(red: 0.62, green: 0.38, blue: 0.78),
                              angle: 135),
        paddingFraction: 0.11,
        cornerRadius: 16,
        shadow: .deep,
        showsWindowFrame: true,
        aspect: .wide,
        title: "",
        subtitle: "",
        textColor: .white,
        isBuiltIn: true)

    static let docs = StylePreset(
        id: "docs",
        name: String(localized: "Docs"),
        background: .solid(.white),
        paddingFraction: 0.03,
        cornerRadius: 6,
        shadow: ShadowStyle(radius: 10, opacity: 0.12, offsetY: 4),
        showsWindowFrame: false,
        aspect: .original,
        title: "",
        subtitle: "",
        textColor: RGBAColor(red: 0.2, green: 0.2, blue: 0.22),
        isBuiltIn: true)

    static let social = StylePreset(
        id: "social",
        name: String(localized: "Social"),
        background: .gradient(start: RGBAColor(red: 0.99, green: 0.65, blue: 0.35),
                              end: RGBAColor(red: 0.92, green: 0.31, blue: 0.45),
                              angle: 120),
        paddingFraction: 0.10,
        cornerRadius: 18,
        shadow: .deep,
        showsWindowFrame: true,
        aspect: .square,
        title: "",
        subtitle: "",
        textColor: .white,
        isBuiltIn: true)
}

/// User-saved presets, stored next to the preferences.
@MainActor
final class StylePresetStore: ObservableObject {
    static let shared = StylePresetStore()

    private static let key = "app.snaplet.stylePresets"
    @Published private(set) var custom: [StylePreset] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([StylePreset].self, from: data) {
            custom = decoded
        }
    }

    var all: [StylePreset] { StylePreset.builtIn + custom }

    func preset(withID id: String) -> StylePreset {
        all.first { $0.id == id } ?? .clean
    }

    func save(_ preset: StylePreset) {
        var stored = preset
        stored.isBuiltIn = false
        if let index = custom.firstIndex(where: { $0.id == stored.id }) {
            custom[index] = stored
        } else {
            custom.append(stored)
        }
        persist()
    }

    func delete(id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
