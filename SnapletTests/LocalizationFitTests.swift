import AppKit
import XCTest
@testable import Snaplet

/// Checks that translated text actually fits the places it is drawn.
///
/// Turkish labels run noticeably longer than their English originals, and a
/// segmented control or a fixed-width panel truncates silently rather than
/// complaining — so these are measured rather than eyeballed.
final class LocalizationFitTests: XCTestCase {

    private let controlFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    private func width(_ text: String, font: NSFont? = nil) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font ?? controlFont]).width)
    }

    /// Rough width a segmented control needs: each segment is its label plus
    /// padding, with a divider between them.
    private func segmentedWidth(_ labels: [String]) -> CGFloat {
        labels.reduce(0) { $0 + width($1) + 22 } + CGFloat(labels.count)
    }

    private func localized(_ key: String, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private var languages: [String] { ["en", "tr"] }

    // MARK: - Segmented controls

    func testTheHistoryFilterFitsItsWidth() {
        for language in languages {
            let labels = ["All", "Images", "Videos"].map { localized($0, language: language) }
            XCTAssertLessThanOrEqual(segmentedWidth(labels), 240,
                                     "history filter overflows in \(language): \(labels)")
        }
    }

    func testTheEditorInspectorTabsFitTheInspector() {
        for language in languages {
            let labels = ["Annotate", "Style", "Text"].map { localized($0, language: language) }
            XCTAssertLessThanOrEqual(segmentedWidth(labels), 268 - 16,
                                     "inspector tabs overflow in \(language): \(labels)")
        }
    }

    // MARK: - Fixed-width panels

    func testTheRecordingCountdownFitsTheControl() {
        // "Starting in 3" and its translations, plus the dot, spacing and buttons.
        for language in languages {
            let template = localized("Starting in %lld", language: language)
            let text = template.replacingOccurrences(of: "%lld", with: "3")
            let needed = 14 + 10 + 8
                + width(text, font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
                + 8 + 34 + 14
            XCTAssertLessThanOrEqual(needed, 320,
                                     "countdown label needs \(needed) pt in \(language): \(text)")
        }
    }

    func testTheSelectionHintFitsATypicalDisplay() {
        // The narrowest display Snaplet is likely to run on, less its margins.
        let available: CGFloat = 1280 - 48
        for language in languages {
            let key = "Drag to select · Space to move · ⇧ square · ⌥ from center · C copies the colour · Esc to cancel"
            let text = localized(key, language: language)
            let needed = width(text, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium)) + 40
            XCTAssertLessThanOrEqual(needed, available,
                                     "selection hint needs \(needed) pt in \(language)")
        }
    }

    // MARK: - Settings

    func testSettingsControlLabelsLeaveRoomForTheirControls() {
        let keys = [
            "Copy captures to the clipboard",
            "Save captures to a folder automatically",
            "Show the preview panel after a capture",
            "Play a sound when a capture succeeds",
            "Delay before capturing",
            "Keep a local history of captures",
            "Highlight mouse clicks",
            "Screen & System Audio Recording"
        ]
        // Window content, less the form's insets, less room for the control.
        let available: CGFloat = 620 - 60 - 170
        for language in languages {
            for key in keys {
                let text = localized(key, language: language)
                XCTAssertLessThanOrEqual(width(text), available,
                                         "\"\(text)\" needs \(width(text)) pt in \(language)")
            }
        }
    }

    func testSettingsTabsFitTheWindow() {
        let keys = ["General", "Shortcuts", "Image", "Recording", "Library", "About"]
        for language in languages {
            let labels = keys.map { localized($0, language: language) }
            // Icon, gap, label and padding per tab.
            let needed = labels.reduce(0) { $0 + 18 + 5 + width($1) + 20 }
            XCTAssertLessThanOrEqual(needed, 620,
                                     "settings tabs need \(needed) pt in \(language): \(labels)")
        }
    }

    // MARK: - The catalogue itself

    func testEveryStringHasATurkishTranslation() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable",
                                                withExtension: "strings",
                                                subdirectory: "tr.lproj"),
                                "the Turkish strings file is missing from the bundle")
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertGreaterThan(table.count, 300, "the Turkish table looks truncated")

        // A translation byte-identical to a real English sentence means the
        // string was skipped. Counting only alphabetic words keeps format
        // strings like "%lld × %lld px" out of it, since those are the same in
        // every language.
        let suspicious = table.filter { key, value in
            guard key == value else { return false }
            let words = key.split(whereSeparator: { !$0.isLetter })
                .filter { $0.count > 1 }
            return words.count > 3
        }
        XCTAssertTrue(suspicious.isEmpty, "untranslated sentences: \(suspicious.keys.sorted())")
    }
}
