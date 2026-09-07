import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private unowned let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Snaplet Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 560, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
