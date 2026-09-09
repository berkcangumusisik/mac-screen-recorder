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
            // Resizable so larger accessibility text sizes are not clipped.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 540))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
