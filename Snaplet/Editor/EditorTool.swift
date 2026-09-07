import Foundation

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case crop
    case arrow
    case line
    case rectangle
    case ellipse
    case freehand
    case highlighter
    case text
    case callout
    case step
    case magnifier
    case blur
    case pixelate
    case redaction

    var id: String { rawValue }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .select, .crop: return nil
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .freehand: return .freehand
        case .highlighter: return .highlighter
        case .text: return .text
        case .callout: return .callout
        case .step: return .step
        case .magnifier: return .magnifier
        case .blur: return .blur
        case .pixelate: return .pixelate
        case .redaction: return .redaction
        }
    }

    var title: String {
        switch self {
        case .select: return String(localized: "Select")
        case .crop: return String(localized: "Crop")
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .freehand: return String(localized: "Draw")
        case .highlighter: return String(localized: "Highlight")
        case .text: return String(localized: "Text")
        case .callout: return String(localized: "Callout")
        case .step: return String(localized: "Step number")
        case .magnifier: return String(localized: "Magnifier")
        case .blur: return String(localized: "Blur")
        case .pixelate: return String(localized: "Pixelate")
        case .redaction: return String(localized: "Redact")
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "scribble"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .callout: return "bubble.left"
        case .step: return "1.circle"
        case .magnifier: return "magnifyingglass.circle"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .redaction: return "rectangle.fill"
        }
    }

    /// Single-key shortcut used inside the editor.
    var keyEquivalent: String {
        switch self {
        case .select: return "v"
        case .crop: return "c"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .freehand: return "d"
        case .highlighter: return "h"
        case .text: return "t"
        case .callout: return "b"
        case .step: return "s"
        case .magnifier: return "m"
        case .blur: return "u"
        case .pixelate: return "p"
        case .redaction: return "x"
        }
    }

    static let drawingTools: [EditorTool] = [
        .select, .crop, .arrow, .line, .rectangle, .ellipse,
        .freehand, .highlighter, .text, .callout, .step, .magnifier
    ]

    static let privacyTools: [EditorTool] = [.redaction, .blur, .pixelate]
}
