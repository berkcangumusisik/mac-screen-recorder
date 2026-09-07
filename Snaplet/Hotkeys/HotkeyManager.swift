import AppKit
import Carbon.HIToolbox

/// Registers Carbon global hot keys. Carbon's `RegisterEventHotKey` is used
/// deliberately: unlike an `NSEvent` global monitor it does not require
/// Accessibility permission and it never observes keystrokes that are not the
/// registered combinations.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Reported for shortcuts that could not be registered (usually because
    /// another application already owns the combination).
    private(set) var failures: [HotkeyAction: String] = [:]

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: (action: HotkeyAction, ref: EventHotKeyRef)] = [:]
    private var identifiers: [HotkeyAction: UInt32] = [:]
    private var nextIdentifier: UInt32 = 1
    private var handler: ((HotkeyAction) -> Void)?

    private static let signature: OSType = 0x534E504C // 'SNPL'

    private init() {}

    func setHandler(_ handler: @escaping (HotkeyAction) -> Void) {
        self.handler = handler
    }

    /// Replaces every registration with `shortcuts`. Actions mapped to `nil`
    /// stay unbound.
    @discardableResult
    func apply(_ shortcuts: [HotkeyAction: KeyboardShortcut?]) -> [HotkeyAction: String] {
        installEventHandlerIfNeeded()
        unregisterAll()
        failures.removeAll()

        for action in HotkeyAction.allCases {
            guard let shortcut = shortcuts[action] ?? nil else { continue }
            guard shortcut.isAcceptable else {
                failures[action] = String(localized: "Needs at least one of ⌘, ⌥ or ⌃.")
                continue
            }
            register(shortcut, for: action)
        }
        return failures
    }

    private func register(_ shortcut: KeyboardShortcut, for action: HotkeyAction) {
        let identifier = nextIdentifier
        nextIdentifier += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            let message: String
            if status == OSStatus(eventHotKeyExistsErr) {
                message = String(localized: "Already used by another application.")
            } else {
                message = String(localized: "System error \(Int(status)).")
            }
            failures[action] = message
            Log.hotkeys.error("Failed to register \(action.rawValue, privacy: .public): \(status)")
            return
        }
        registrations[identifier] = (action, ref)
        identifiers[action] = identifier
    }

    func unregisterAll() {
        for (_, registration) in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        identifiers.removeAll()
    }

    fileprivate func fire(identifier: UInt32) {
        guard let registration = registrations[identifier] else { return }
        handler?(registration.action)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotkeyManager.signature else { return status }
            let identifier = hotKeyID.id
            DispatchQueue.main.async {
                HotkeyManager.shared.fire(identifier: identifier)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
