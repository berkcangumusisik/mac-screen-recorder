import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snaplet

final class ShortcutAndNamingTests: XCTestCase {

    func testCarbonModifiersMapFromAppKitFlags() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A),
                                        modifiers: [.command, .shift, .option, .control])
        let expected = UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey)
        XCTAssertEqual(shortcut.carbonModifiers, expected)
    }

    func testUnsupportedModifiersAreDropped() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A),
                                        modifiers: [.command, .capsLock, .function])
        XCTAssertEqual(shortcut.modifiers, [.command])
    }

    func testShortcutsWithoutACommandModifierAreRejected() {
        XCTAssertFalse(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: []).isAcceptable)
        XCTAssertFalse(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift]).isAcceptable)
        XCTAssertTrue(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.control]).isAcceptable)
    }

    func testDefaultShortcutsAreUniqueAndAvoidTheSystemScreenshotKeys() {
        var seen = Set<String>()
        for action in HotkeyAction.allCases {
            let shortcut = action.defaultShortcut
            XCTAssertTrue(shortcut.isAcceptable, "\(action.rawValue) needs a real modifier")
            let key = "\(shortcut.keyCode)-\(shortcut.modifierFlags)"
            XCTAssertFalse(seen.contains(key), "\(action.rawValue) duplicates another default")
            seen.insert(key)

            // macOS uses ⇧⌘3/4/5/6; Snaplet's defaults must not be ⇧⌘-only.
            let isShiftCommandOnly = shortcut.modifiers == [.shift, .command]
            XCTAssertFalse(isShiftCommandOnly, "\(action.rawValue) collides with the system screenshot shortcuts")
        }
    }

    func testShortcutRoundTripsThroughJSON() throws {
        let original = KeyboardShortcut(keyCode: 12, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: data), original)
    }

    func testPreferencesFallBackToDefaultShortcutsAndHonourExplicitUnbinding() {
        var preferences = Preferences()
        XCTAssertEqual(preferences.shortcut(for: .captureArea), HotkeyAction.captureArea.defaultShortcut)

        preferences.shortcuts[HotkeyAction.captureArea.rawValue] = .some(nil)
        XCTAssertNil(preferences.shortcut(for: .captureArea))
    }

    func testFileNameIsStableAndSortable() {
        let date = Date(timeIntervalSince1970: 1_757_270_103) // 2025-09-07 in UTC
        let name = OutputNaming.fileName(prefix: "Snaplet", date: date, fileExtension: "png")
        XCTAssertTrue(name.hasPrefix("Snaplet "))
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertTrue(name.contains(" at "))
    }

    func testUniqueURLAvoidsOverwritingAnExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = OutputNaming.uniqueURL(in: directory, fileName: "Shot.png")
        try Data([0]).write(to: first)
        let second = OutputNaming.uniqueURL(in: directory, fileName: "Shot.png")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "Shot 2.png")
    }

    func testAnExplicitlyUnboundShortcutSurvivesAJSONRoundTrip() throws {
        var preferences = Preferences()
        preferences.shortcuts[HotkeyAction.captureArea.rawValue] = .some(nil)
        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertNil(decoded.shortcut(for: .captureArea),
                     "an unbound shortcut must not silently return to its default")
        XCTAssertEqual(decoded.shortcut(for: .captureWindow),
                       HotkeyAction.captureWindow.defaultShortcut)
        XCTAssertNil(decoded.resolvedShortcuts[.captureArea] ?? nil)
    }

    func testPreferencesSurviveAJSONRoundTrip() throws {
        var preferences = Preferences()
        preferences.videoFrameRate = 30
        preferences.resolutionCap = .p1440
        preferences.shortcuts["captureArea"] = .some(KeyboardShortcut(keyCode: 5, modifiers: [.command]))
        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(decoded, preferences)
    }
}
