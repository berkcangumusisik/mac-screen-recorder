import AppKit

/// Single place where failures become something the user can act on.
@MainActor
enum ErrorPresenter {

    static func present(_ error: SnapletError) {
        switch error {
        case .screenRecordingPermissionDenied:
            presentPermission(error, pane: .screenRecording)
        case .microphonePermissionDenied:
            presentPermission(error, pane: .microphone)
        case .cameraPermissionDenied:
            presentPermission(error, pane: .camera)
        case .selectionCancelled, .exportCancelled:
            return
        default:
            presentSimple(error)
        }
    }

    private static func presentSimple(_ error: SnapletError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.errorDescription ?? String(localized: "Something went wrong.")
        if let suggestion = error.recoverySuggestion { alert.informativeText = suggestion }
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func presentPermission(_ error: SnapletError, pane: PermissionsService.Pane) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = error.errorDescription ?? ""
        alert.informativeText = error.recoverySuggestion ?? ""
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsService.shared.openSystemSettings(pane)
        }
    }
}
