import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only until a window is actually needed.
        NSApp.setActivationPolicy(.accessory)
        // Unit tests use this app as their host; starting the menu bar item and
        // registering global hot keys there would leak into the user's session.
        guard NSClassFromString("XCTestCase") == nil else { return }
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { environment.showSettings() }
        return true
    }
}
