import AVFoundation
import AppKit
import ScreenCaptureKit

/// Tracks the three privacy permissions Snaplet can need, and knows how to ask
/// for each one. Nothing is requested until the matching feature is used.
@MainActor
final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    enum Status: Equatable {
        case authorized
        case denied
        case undetermined

        var isAuthorized: Bool { self == .authorized }
    }

    enum Pane: String {
        case screenRecording = "Privacy_ScreenCapture"
        case microphone = "Privacy_Microphone"
        case camera = "Privacy_Camera"
    }

    @Published private(set) var screenRecording: Status = .undetermined
    @Published private(set) var microphone: Status = .undetermined
    @Published private(set) var camera: Status = .undetermined

    private init() {
        refresh()
    }

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess() ? .authorized : .denied
        microphone = Self.status(for: .audio)
        camera = Self.status(for: .video)
    }

    private static func status(for mediaType: AVMediaType) -> Status {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return .authorized
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    /// Triggers the system prompt the first time, and afterwards simply reports
    /// the stored answer. Callers should offer `openSystemSettings` when this
    /// returns `false`.
    @discardableResult
    func ensureScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenRecording = .authorized
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        screenRecording = granted ? .authorized : .denied
        if !granted {
            Log.permissions.notice("Screen recording permission not granted")
        }
        return granted
    }

    @discardableResult
    func ensureMicrophone() async -> Bool {
        let granted = await Self.request(.audio)
        microphone = granted ? .authorized : .denied
        return granted
    }

    @discardableResult
    func ensureCamera() async -> Bool {
        let granted = await Self.request(.video)
        camera = granted ? .authorized : .denied
        return granted
    }

    private static func request(_ mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    func openSystemSettings(_ pane: Pane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
