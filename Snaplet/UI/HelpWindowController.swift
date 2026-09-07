import AppKit
import SwiftUI

/// Compact shortcut reference. Kept deliberately small: it is a reminder, not
/// documentation.
@MainActor
final class HelpWindowController {

    private var window: NSWindow?
    private unowned let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Snaplet Shortcuts")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 460))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    let environment: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared
    @State private var performanceReport = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section(String(localized: "Global shortcuts")) {
                    ForEach(HotkeyAction.allCases) { action in
                        HStack {
                            Label(action.title, systemImage: action.symbolName)
                            Spacer()
                            Text(settings.preferences.shortcut(for: action)?.displayString
                                 ?? String(localized: "Not set"))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section(String(localized: "While selecting")) {
                    helpRow(String(localized: "Constrain to a square"), "⇧ drag")
                    helpRow(String(localized: "Draw from the centre"), "⌥ drag")
                    helpRow(String(localized: "Move the selection"), String(localized: "Hold Space"))
                    helpRow(String(localized: "Cancel"), "Esc")
                }
                Section(String(localized: "Session measurements")) {
                    Text(performanceReport.isEmpty
                         ? String(localized: "Use Snaplet for a moment, then refresh.")
                         : performanceReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button(String(localized: "Refresh")) {
                            performanceReport = Metrics.shared.report()
                        }
                        Button(String(localized: "Copy")) {
                            Clipboard.copy(text: Metrics.shared.report())
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 420, minHeight: 420)
        .onAppear { performanceReport = Metrics.shared.report() }
    }

    private func helpRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
