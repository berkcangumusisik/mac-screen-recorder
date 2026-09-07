import AppKit
import SwiftUI

@MainActor
final class VideoEditorPresenter: NSObject, NSWindowDelegate {

    private unowned let environment: AppEnvironment
    private var windows: [ObjectIdentifier: NSWindow] = [:]

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func present(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ErrorPresenter.present(.exportFailed("that file is no longer on disk"))
            return
        }
        let hosting = NSHostingController(rootView: VideoEditorView(url: url, environment: environment))
        let window = NSWindow(contentViewController: hosting)
        window.title = url.lastPathComponent
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows[ObjectIdentifier(window)] = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.delegate = nil
        windows.removeValue(forKey: ObjectIdentifier(window))
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0 is NSPanel }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
