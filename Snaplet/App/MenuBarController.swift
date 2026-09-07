import AppKit

/// The status-bar item. Snaplet has no dock icon and no main window, so this is
/// the only permanently visible surface.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private weak var environment: AppEnvironment?

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: String(localized: "Snaplet"))
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Shows the elapsed recording time next to the icon while recording.
    func setRecordingIndicator(_ text: String?) {
        guard let button = statusItem.button else { return }
        button.title = text.map { " \($0)" } ?? ""
        button.image = NSImage(systemSymbolName: text == nil ? "camera.viewfinder" : "record.circle",
                               accessibilityDescription: String(localized: "Snaplet"))
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let environment else { return }

        addAction(.captureArea, to: menu)
        addAction(.captureWindow, to: menu)
        addAction(.captureFullScreen, to: menu)
        addAction(.repeatLastArea, to: menu, enabled: environment.captureCoordinator.hasLastArea)
        menu.addItem(.separator())

        addAction(.toggleRecording, to: menu, title: environment.recordingMenuTitle)
        menu.addItem(.separator())

        addAction(.copyTextOnScreen, to: menu)
        addAction(.editClipboardImage, to: menu)
        menu.addItem(.separator())

        menu.addItem(item(title: String(localized: "History…"),
                          action: #selector(openHistory),
                          keyEquivalent: ""))
        menu.addItem(item(title: String(localized: "Settings…"),
                          action: #selector(openSettings),
                          keyEquivalent: ","))
        menu.addItem(item(title: String(localized: "Keyboard Shortcuts…"),
                          action: #selector(openHelp),
                          keyEquivalent: "/"))
        menu.addItem(.separator())
        menu.addItem(item(title: String(localized: "Quit Snaplet"),
                          action: #selector(quit),
                          keyEquivalent: "q"))
    }

    private func addAction(_ action: HotkeyAction,
                           to menu: NSMenu,
                           title: String? = nil,
                           enabled: Bool = true) {
        let menuItem = NSMenuItem(title: title ?? action.title,
                                  action: #selector(performHotkeyAction(_:)),
                                  keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = action.rawValue
        menuItem.isEnabled = enabled
        menuItem.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
        if let shortcut = environment?.settings.preferences.shortcut(for: action) {
            menuItem.keyEquivalent = shortcutKeyEquivalent(shortcut)
            menuItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(menuItem)
    }

    /// Menu items show the shortcut for discoverability; the global hot key is
    /// what actually fires when Snaplet is in the background.
    private func shortcutKeyEquivalent(_ shortcut: KeyboardShortcut) -> String {
        let label = KeyCodeTranslator.label(for: shortcut.keyCode)
        guard label.count == 1 else { return "" }
        return label.lowercased()
    }

    private func item(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        return menuItem
    }

    @objc private func performHotkeyAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = HotkeyAction(rawValue: raw) else { return }
        environment?.perform(action)
    }

    @objc private func openSettings() { environment?.showSettings() }
    @objc private func openHistory() { environment?.showHistory() }
    @objc private func openHelp() { environment?.showHelp() }
    @objc private func quit() { NSApp.terminate(nil) }
}
