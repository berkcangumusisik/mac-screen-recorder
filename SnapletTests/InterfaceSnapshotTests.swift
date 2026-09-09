import AppKit
import SwiftUI
import XCTest
@testable import Snaplet

/// Renders the floating surfaces to image files so their layout can actually be
/// looked at during development, in both appearances, without launching the app
/// or needing any permission.
///
/// Output goes to `SNAPLET_UI_SNAPSHOTS` (default: a temporary directory whose
/// path is printed). The assertions only check that a view renders at all —
/// these are a development aid, not pixel comparisons that would break on every
/// system font change.
@MainActor
final class InterfaceSnapshotTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment["SNAPLET_UI_SNAPSHOTS"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("snaplet-ui").path
        directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func render(_ name: String,
                        size: CGSize,
                        @ViewBuilder content: () -> some View) throws {
        for scheme in [ColorScheme.light, .dark] {
            let backdrop = scheme == .dark
                ? Color(red: 0.12, green: 0.12, blue: 0.13)
                : Color(red: 0.90, green: 0.90, blue: 0.92)

            let view = ZStack {
                backdrop
                content()
            }
            .frame(width: size.width + 40, height: size.height + 40)
            .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "\(name) did not render")
            let representation = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            let suffix = scheme == .dark ? "dark" : "light"
            try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    func testRendersEveryFloatingSurface() throws {
        let image = TestImages.split(width: 640, height: 400)

        // Recording control, in each of the states it can be in.
        for (name, configure) in [
            ("control-recording", { (model: RecordingControlModel) in model.elapsed = 83 }),
            ("control-paused", { model in model.elapsed = 83; model.isPaused = true }),
            ("control-countdown", { model in model.isCountingDown = true; model.countdown = 3 })
        ] as [(String, (RecordingControlModel) -> Void)] {
            let model = RecordingControlModel()
            configure(model)
            try render(name, size: CGSize(width: 232, height: 48)) {
                RecordingControlView(model: model).frame(width: 232)
            }
        }

        // The preview panel, saved and unsaved.
        let unsaved = PendingCapture(result: CaptureResult(image: image, scale: 2, source: .clipboard),
                                     savedURL: nil)
        try render("preview-unsaved", size: CGSize(width: 300, height: 206)) {
            CapturePreviewView(capture: unsaved,
                               onEdit: {}, onSave: {}, onBugReport: {},
                               onPin: {}, onClose: {}, onHoverChange: { _ in })
                .frame(width: 300)
        }

        let saved = PendingCapture(result: CaptureResult(image: image, scale: 2, source: .clipboard),
                                   savedURL: URL(fileURLWithPath: "/tmp/Snaplet 2026-09-09 at 09.30.00.png"))
        try render("preview-saved", size: CGSize(width: 300, height: 206)) {
            CapturePreviewView(capture: saved,
                               onEdit: {}, onSave: {}, onBugReport: {},
                               onPin: {}, onClose: {}, onHoverChange: { _ in })
                .frame(width: 300)
        }

        // A pinned capture.
        let shot = PinnedShot(image: image, scale: 2, capturedAt: Date())
        try render("pinned", size: CGSize(width: 320, height: 200)) {
            PinnedShotView(shot: shot, onClose: {})
                .frame(width: 320, height: 200)
        }

        print("UI SNAPSHOTS: \(directory.path)")
    }

    /// The settings window, pane by pane. These are the only surfaces in Snaplet
    /// that people read rather than glance at, so their spacing and grouping
    /// matter more than anywhere else.
    func testRendersEverySettingsPane() throws {
        let environment = AppEnvironment()
        let size = CGSize(width: 560, height: 520)

        try render("settings-general", size: size) {
            GeneralSettingsView(environment: environment).frame(width: size.width, height: size.height)
        }
        try render("settings-image", size: size) {
            ImageSettingsView().frame(width: size.width, height: size.height)
        }
        try render("settings-recording", size: size) {
            RecordingSettingsView(environment: environment).frame(width: size.width, height: size.height)
        }
        try render("settings-library", size: size) {
            LibrarySettingsView(environment: environment).frame(width: size.width, height: size.height)
        }
        try render("settings-about", size: size) {
            AboutSettingsView().frame(width: size.width, height: size.height)
        }
        try render("settings-shortcuts", size: size) {
            ShortcutSettingsView(environment: environment).frame(width: size.width, height: size.height)
        }
    }

    /// Control: does `ImageRenderer` draw a bare `Menu` at all? If it cannot,
    /// the placeholder in the preview snapshots is a limitation of rendering
    /// offscreen, not something wrong with the panel.
    func testWhetherMenusRenderOffscreenAtAll() throws {
        try render("control-menu-vs-button", size: CGSize(width: 200, height: 44)) {
            HStack(spacing: 10) {
                Button { } label: { Image(systemName: "ellipsis") }
                Menu { Button("One") { } } label: { Image(systemName: "ellipsis") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 200)
        }
    }
}
