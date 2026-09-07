import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Thin, testable wrapper over ScreenCaptureKit's still-image APIs.
///
/// Every capture excludes Snaplet's own windows, so overlays, the preview panel
/// and the recording control never end up in a screenshot.
struct ScreenshotService {

    func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Captures every connected display. Returns snapshots in `NSScreen.screens`
    /// order, so index 0 is the primary display.
    @MainActor
    func captureAllDisplays() async throws -> [DisplaySnapshot] {
        let content = try await shareableContent()
        var snapshots: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            if let snapshot = try await captureDisplay(screen: screen, content: content) {
                snapshots.append(snapshot)
            }
        }
        guard !snapshots.isEmpty else { throw SnapletError.noCaptureSource }
        return snapshots
    }

    /// Captures one display at its native pixel size, excluding Snaplet itself.
    /// Returns `nil` when the screen is not currently shareable.
    @MainActor
    func captureDisplay(screen: NSScreen, content: SCShareableContent) async throws -> DisplaySnapshot? {
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }

        let ownApplication = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let scale = screen.backingScaleFactor
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplication.map { [$0] } ?? [],
                                     exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int((screen.frame.width * scale).rounded())
        configuration.height = Int((screen.frame.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.scalesToFit = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: configuration)
            return DisplaySnapshot(displayID: displayID,
                                   frame: screen.frame,
                                   scale: scale,
                                   image: image)
        } catch {
            Log.capture.error("Display capture failed: \(error.localizedDescription, privacy: .public)")
            throw Self.mapped(error)
        }
    }

    /// Captures a single window on its own, without anything stacked on top.
    func captureWindow(_ window: SCWindow) async throws -> CaptureResult {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                  configuration: configuration)
            return CaptureResult(image: image,
                                 scale: scale > 0 ? scale : 2,
                                 source: .window(windowID: window.windowID, title: window.title))
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Lists pickable windows, front to back, converted into AppKit coordinates.
    @MainActor
    func windowCandidates(from content: SCShareableContent, geometry: ScreenGeometry) -> [WindowCandidate] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= 20, window.frame.height >= 20,
                  let owner = window.owningApplication,
                  owner.bundleIdentifier != ownBundleID else { return nil }
            return WindowCandidate(scWindow: window,
                                   appKitFrame: geometry.appKitRect(fromCG: window.frame),
                                   applicationName: owner.applicationName,
                                   title: window.title)
        }
    }

    private static func mapped(_ error: Error) -> SnapletError {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            return .captureFailed(nsError.localizedDescription)
        }
        switch nsError.code {
        case -3801, -3803: // userDeclined, missingEntitlements
            return .screenRecordingPermissionDenied
        case -3813, -3814, -3815: // noWindowList, noDisplayList, noCaptureSource
            return .noCaptureSource
        default:
            return .captureFailed(nsError.localizedDescription)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
