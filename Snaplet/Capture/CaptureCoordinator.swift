import AppKit
import ScreenCaptureKit

@MainActor
protocol CaptureCoordinatorDelegate: AnyObject {
    func captureCoordinator(_ coordinator: CaptureCoordinator, didProduce result: CaptureResult)
    func captureCoordinator(_ coordinator: CaptureCoordinator, didFail error: SnapletError)
}

/// Owns the still-capture flows and the "last area" memory.
///
/// A single `isBusy` flag makes repeated hot-key presses idempotent instead of
/// stacking overlays on top of each other.
@MainActor
final class CaptureCoordinator {

    weak var delegate: CaptureCoordinatorDelegate?

    private let screenshots = ScreenshotService()
    private let overlay = SelectionOverlayController()
    private var isBusy = false

    private struct LastArea {
        let displayID: CGDirectDisplayID
        /// Global AppKit points.
        let rect: CGRect
    }

    private var lastArea: LastArea?

    var hasLastArea: Bool { lastArea != nil }

    // MARK: - Flows

    func captureArea() async {
        await run { [self] in
            let start = ContinuousClock.now
            let snapshots = try await screenshots.captureAllDisplays()
            Metrics.shared.record(MetricName.shortcutToOverlay, duration: start.secondsElapsed)

            let outcome = await overlay.present(mode: .area, snapshots: snapshots, candidates: [])
            guard case .area(let snapshot, let rect) = outcome else { return nil }

            let deliveryStart = ContinuousClock.now
            guard let cropRect = ScreenGeometry.pixelCropRect(selection: rect,
                                                              inDisplayFrame: snapshot.frame,
                                                              scale: snapshot.scale,
                                                              imagePixelSize: snapshot.pixelSize),
                  let cropped = snapshot.image.cropping(to: cropRect) else {
                throw SnapletError.captureFailed("selection was empty")
            }
            lastArea = LastArea(displayID: snapshot.displayID, rect: rect)
            let result = CaptureResult(image: cropped,
                                       scale: snapshot.scale,
                                       source: .area(displayID: snapshot.displayID, rect: rect))
            Metrics.shared.record(MetricName.selectionToClipboard, duration: deliveryStart.secondsElapsed)
            return result
        }
    }

    func captureWindow() async {
        await run { [self] in
            let content = try await screenshots.shareableContent()
            let snapshots = try await screenshots.captureAllDisplays()
            let candidates = screenshots.windowCandidates(from: content, geometry: .current)
            guard !candidates.isEmpty else { throw SnapletError.noCaptureSource }

            let outcome = await overlay.present(mode: .window, snapshots: snapshots, candidates: candidates)
            guard case .window(let candidate) = outcome else { return nil }

            let start = ContinuousClock.now
            // The window may have closed while the picker was open.
            let fresh = try await screenshots.shareableContent()
            guard fresh.windows.contains(where: { $0.windowID == candidate.scWindow.windowID }) else {
                throw SnapletError.targetDisappeared
            }
            let result = try await screenshots.captureWindow(candidate.scWindow)
            Metrics.shared.record(MetricName.windowCapture, duration: start.secondsElapsed)
            return result
        }
    }

    func captureFullScreen() async {
        await run { [self] in
            let start = ContinuousClock.now
            let screen = NSScreen.screenUnderMouse ?? NSScreen.main
            guard let screen else { throw SnapletError.noCaptureSource }
            let content = try await screenshots.shareableContent()
            guard let snapshot = try await screenshots.captureDisplay(screen: screen, content: content) else {
                throw SnapletError.noCaptureSource
            }
            let result = CaptureResult(image: snapshot.image,
                                       scale: snapshot.scale,
                                       source: .fullScreen(displayID: snapshot.displayID))
            Metrics.shared.record(MetricName.fullScreenCapture, duration: start.secondsElapsed)
            return result
        }
    }

    /// Re-captures the last area. The display is looked up again and the stored
    /// rect is re-validated, so unplugging or rearranging monitors cannot
    /// produce a capture from the wrong place.
    func repeatLastArea() async {
        guard let lastArea else {
            await captureArea()
            return
        }
        await run { [self] in
            guard let screen = NSScreen.screens.first(where: { $0.displayID == lastArea.displayID }) else {
                self.lastArea = nil
                throw SnapletError.displayDisconnected
            }
            let clipped = lastArea.rect.intersection(screen.frame)
            guard clipped.width >= 2, clipped.height >= 2 else {
                self.lastArea = nil
                throw SnapletError.displayDisconnected
            }
            let content = try await screenshots.shareableContent()
            guard let snapshot = try await screenshots.captureDisplay(screen: screen, content: content) else {
                throw SnapletError.noCaptureSource
            }
            guard let cropRect = ScreenGeometry.pixelCropRect(selection: clipped,
                                                              inDisplayFrame: snapshot.frame,
                                                              scale: snapshot.scale,
                                                              imagePixelSize: snapshot.pixelSize),
                  let cropped = snapshot.image.cropping(to: cropRect) else {
                throw SnapletError.captureFailed("stored area no longer valid")
            }
            return CaptureResult(image: cropped,
                                 scale: snapshot.scale,
                                 source: .area(displayID: snapshot.displayID, rect: clipped))
        }
    }

    /// Returns the current area selection without delivering it, for flows that
    /// want the region rather than the pixels (OCR, for example).
    func selectAreaForRecognition() async -> CaptureResult? {
        guard !isBusy, await ensurePermission() else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let snapshots = try await screenshots.captureAllDisplays()
            let outcome = await overlay.present(mode: .area, snapshots: snapshots, candidates: [])
            guard case .area(let snapshot, let rect) = outcome,
                  let cropRect = ScreenGeometry.pixelCropRect(selection: rect,
                                                              inDisplayFrame: snapshot.frame,
                                                              scale: snapshot.scale,
                                                              imagePixelSize: snapshot.pixelSize),
                  let cropped = snapshot.image.cropping(to: cropRect) else { return nil }
            lastArea = LastArea(displayID: snapshot.displayID, rect: rect)
            return CaptureResult(image: cropped,
                                 scale: snapshot.scale,
                                 source: .area(displayID: snapshot.displayID, rect: rect))
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: - Plumbing

    private func run(_ body: () async throws -> CaptureResult?) async {
        guard !isBusy else {
            Log.capture.debug("Capture request ignored: another capture is in flight")
            return
        }
        guard await ensurePermission() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let result = try await body() {
                delegate?.captureCoordinator(self, didProduce: result)
            }
        } catch {
            report(error)
        }
    }

    private func ensurePermission() async -> Bool {
        if await PermissionsService.shared.ensureScreenRecording() { return true }
        delegate?.captureCoordinator(self, didFail: .screenRecordingPermissionDenied)
        return false
    }

    private func report(_ error: Error) {
        let mapped = (error as? SnapletError) ?? .captureFailed(error.localizedDescription)
        if mapped == .selectionCancelled { return }
        Log.capture.error("Capture failed: \(mapped.localizedDescription, privacy: .public)")
        delegate?.captureCoordinator(self, didFail: mapped)
    }
}

extension NSScreen {
    /// The screen containing the pointer, which is what "full screen" should
    /// mean on a multi-display setup.
    @MainActor
    static var screenUnderMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}

extension ContinuousClock.Instant {
    var secondsElapsed: TimeInterval {
        let duration = self.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
