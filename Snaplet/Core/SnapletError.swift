import Foundation

/// One error type for every user-visible failure in Snaplet.
///
/// Every case carries a short, actionable message. Errors are surfaced through
/// `ErrorPresenter` rather than raw `NSError` alerts.
enum SnapletError: LocalizedError, Equatable {
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    case cameraPermissionDenied
    case noCaptureSource
    case captureFailed(String)
    case targetDisappeared
    case displayDisconnected
    case selectionCancelled
    case recordingAlreadyActive
    case recordingNotActive
    case recordingSetupFailed(String)
    case recordingWriteFailed(String)
    case diskFull
    case exportFailed(String)
    case exportCancelled
    case unsupportedImageData
    case fileWriteFailed(String)
    case hotkeyRegistrationFailed(String)
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return String(localized: "Snaplet needs Screen & System Audio Recording permission.")
        case .microphonePermissionDenied:
            return String(localized: "Snaplet needs Microphone permission to record narration.")
        case .cameraPermissionDenied:
            return String(localized: "Snaplet needs Camera permission for the webcam overlay.")
        case .noCaptureSource:
            return String(localized: "No display or window is available to capture.")
        case .captureFailed(let detail):
            return String(localized: "Capture failed: \(detail)")
        case .targetDisappeared:
            return String(localized: "The window being captured is no longer available.")
        case .displayDisconnected:
            return String(localized: "The display used for this capture is no longer connected.")
        case .selectionCancelled:
            return String(localized: "Selection cancelled.")
        case .recordingAlreadyActive:
            return String(localized: "A recording is already in progress.")
        case .recordingNotActive:
            return String(localized: "No recording is in progress.")
        case .recordingSetupFailed(let detail):
            return String(localized: "Could not start recording: \(detail)")
        case .recordingWriteFailed(let detail):
            return String(localized: "Recording stopped because of a write error: \(detail)")
        case .diskFull:
            return String(localized: "The output volume is out of free space.")
        case .exportFailed(let detail):
            return String(localized: "Export failed: \(detail)")
        case .exportCancelled:
            return String(localized: "Export cancelled.")
        case .unsupportedImageData:
            return String(localized: "That data is not an image Snaplet can open.")
        case .fileWriteFailed(let detail):
            return String(localized: "Could not write the file: \(detail)")
        case .hotkeyRegistrationFailed(let detail):
            return String(localized: "Shortcut could not be registered: \(detail)")
        case .ocrFailed(let detail):
            return String(localized: "Text recognition failed: \(detail)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return String(localized: "Open System Settings › Privacy & Security › Screen & System Audio Recording and enable Snaplet.")
        case .microphonePermissionDenied:
            return String(localized: "Open System Settings › Privacy & Security › Microphone and enable Snaplet.")
        case .cameraPermissionDenied:
            return String(localized: "Open System Settings › Privacy & Security › Camera and enable Snaplet.")
        case .diskFull:
            return String(localized: "Free up space or choose a different output folder in Settings.")
        default:
            return nil
        }
    }
}
