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

    /// Triggers the system prompt the first time, and afterwards reports whether
    /// capture actually works. Callers should offer `openSystemSettings` when
    /// this returns `false`.
    ///
    /// `CGPreflightScreenCaptureAccess` answers from a value cached per process,
    /// so it keeps saying "no" after the user grants the permission in System
    /// Settings while Snaplet is running. Asking ScreenCaptureKit for the
    /// shareable content is the only answer that reflects reality, so a negative
    /// preflight is treated as a hint and confirmed before anything is reported
    /// to the user.
    @discardableResult
    func ensureScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenRecording = .authorized
            return true
        }

        if await canActuallyCapture() {
            Log.permissions.notice("Preflight reported no screen access, but capture works")
            screenRecording = .authorized
            return true
        }

        // Only prompts the first time; afterwards it returns the stored answer
        // without showing anything, which is why the caller has to explain
        // where the setting lives.
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            screenRecording = .authorized
            return true
        }

        // The prompt is silent once a decision exists, and the user may have
        // just granted it in System Settings, so confirm once more.
        let works = await canActuallyCapture()
        screenRecording = works ? .authorized : .denied
        if !works {
            Log.permissions.notice("Screen recording permission not granted")
        }
        return works
    }

    /// The authoritative check: can Snaplet enumerate shareable content?
    private func canActuallyCapture() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return false
        }
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
