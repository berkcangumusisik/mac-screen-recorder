import AppKit
import Carbon.HIToolbox

/// Everything Snaplet can be triggered to do from a global shortcut.
///
/// Defaults deliberately use ⌃⌥⌘ so they do not collide with the macOS
/// screenshot shortcuts (⇧⌘3/4/5/6) or common app shortcuts.
enum HotkeyAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case captureArea
    case captureWindow
    case captureFullScreen
    case repeatLastArea
    case toggleRecording
    case copyTextOnScreen
    case editClipboardImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureArea: return String(localized: "Capture Area")
        case .captureWindow: return String(localized: "Capture Window")
        case .captureFullScreen: return String(localized: "Capture Full Screen")
        case .repeatLastArea: return String(localized: "Repeat Last Area")
        case .toggleRecording: return String(localized: "Start / Stop Recording")
        case .copyTextOnScreen: return String(localized: "Copy Text on Screen")
        case .editClipboardImage: return String(localized: "Edit Clipboard Image")
        }
    }

    var symbolName: String {
        switch self {
        case .captureArea: return "square.dashed"
        case .captureWindow: return "macwindow"
        case .captureFullScreen: return "rectangle.inset.filled"
        case .repeatLastArea: return "arrow.clockwise.square"
        case .toggleRecording: return "record.circle"
        case .copyTextOnScreen: return "text.viewfinder"
        case .editClipboardImage: return "doc.on.clipboard"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        switch self {
        case .captureArea:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: modifiers)
        case .captureWindow:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_W), modifiers: modifiers)
        case .captureFullScreen:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_F), modifiers: modifiers)
        case .repeatLastArea:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_R), modifiers: modifiers)
        case .toggleRecording:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: modifiers)
        case .copyTextOnScreen:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_T), modifiers: modifiers)
        case .editClipboardImage:
            return KeyboardShortcut(keyCode: UInt16(kVK_ANSI_E), modifiers: modifiers)
        }
    }
}
