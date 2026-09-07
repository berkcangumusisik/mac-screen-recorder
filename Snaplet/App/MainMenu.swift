import AppKit

/// Snaplet lives in the menu bar, but its editor, history and settings windows
/// are ordinary windows: without an application menu the standard editing
/// shortcuts (⌘C, ⌘V, ⌘A, ⌘Z) would not work in any text field.
///
/// This installs a minimal, correct main menu and leaves anything the runtime
/// already provided in place.
@MainActor
enum MainMenu {

    static func install(environment: AppEnvironment) {
        let menu = NSApp.mainMenu ?? NSMenu()

        if menu.items.isEmpty {
            menu.addItem(applicationMenuItem(environment: environment))
        }
        if !menu.items.contains(where: { $0.submenu?.title == editMenuTitle }) {
            menu.addItem(editMenuItem())
        }
        if !menu.items.contains(where: { $0.submenu?.title == windowMenuTitle }) {
            let item = windowMenuItem()
            menu.addItem(item)
            NSApp.windowsMenu = item.submenu
        }
        NSApp.mainMenu = menu
    }

    private static let editMenuTitle = String(localized: "Edit", comment: "Main menu title")
    private static let windowMenuTitle = String(localized: "Window", comment: "Main menu title")

    private static func applicationMenuItem(environment: AppEnvironment) -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Snaplet")

        submenu.addItem(withTitle: String(localized: "About Snaplet"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        submenu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "Settings…"),
                                  action: #selector(MenuActions.openSettings),
                                  keyEquivalent: ",")
        settings.target = MenuActions.shared
        submenu.addItem(settings)
        MenuActions.shared.environment = environment

        submenu.addItem(.separator())
        submenu.addItem(withTitle: String(localized: "Hide Snaplet"),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        submenu.addItem(withTitle: String(localized: "Quit Snaplet"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        item.submenu = submenu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: editMenuTitle)
        submenu.addItem(withTitle: String(localized: "Undo"),
                        action: Selector(("undo:")), keyEquivalent: "z")
        let redo = submenu.addItem(withTitle: String(localized: "Redo"),
                                   action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        submenu.addItem(.separator())
        submenu.addItem(withTitle: String(localized: "Cut"),
                        action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        submenu.addItem(withTitle: String(localized: "Copy"),
                        action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        submenu.addItem(withTitle: String(localized: "Paste"),
                        action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        submenu.addItem(withTitle: String(localized: "Select All"),
                        action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = submenu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: windowMenuTitle)
        submenu.addItem(withTitle: String(localized: "Close"),
                        action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        submenu.addItem(withTitle: String(localized: "Minimise"),
                        action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        item.submenu = submenu
        return item
    }
}

/// Target for menu items that need to reach the app environment.
@MainActor
final class MenuActions: NSObject {
    static let shared = MenuActions()
    weak var environment: AppEnvironment?

    @objc func openSettings() {
        environment?.showSettings()
    }
}
