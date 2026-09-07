import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {

    private let document: EditorDocument
    private unowned let environment: AppEnvironment
    private var window: NSWindow?
    var onClose: (() -> Void)?

    init(document: EditorDocument, environment: AppEnvironment) {
        self.document = document
        self.environment = environment
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: EditorView(document: document,
                                                                   environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Snaplet Editor")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1080, height: 720))
            window.minSize = NSSize(width: 820, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        onClose?()
        // Return to the menu-bar-only presentation when no window is left.
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0 is NSPanel }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
