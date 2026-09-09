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
    private let countdown = CountdownOverlay()
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

            overlay.confinesSelectionToOneDisplay = false
            let outcome = await overlay.present(mode: .area, snapshots: snapshots, candidates: [])
            guard case .area(let image, let scale, let rect, let displayID) = outcome else { return nil }

            let deliveryStart = ContinuousClock.now
            lastArea = LastArea(displayID: displayID, rect: rect)

            // With a delay the point is to capture what the screen looks like
            // *after* the wait, so the pre-selection snapshots are thrown away
            // and every display the selection touches is read again.
            var finalImage = image
            var finalScale = scale
            if await runCaptureDelay() {
                let fresh = try await screenshots.captureAllDisplays()
                guard let composed = MultiDisplayCompositor.composite(selection: rect, from: fresh) else {
                    throw SnapletError.captureFailed("the selected area is no longer on screen")
                }
                finalImage = composed.image
                finalScale = composed.scale
            }

            let result = CaptureResult(image: finalImage,
                                       scale: finalScale,
                                       source: .area(displayID: displayID, rect: rect))
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

            _ = await runCaptureDelay()

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
            _ = await runCaptureDelay()

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
            // The stored rectangle may now fall on a display that has been
            // unplugged or moved, so the whole layout is re-read and the area is
            // clipped to whatever is still on screen.
            let snapshots = try await screenshots.captureAllDisplays()
            let covered = snapshots
                .map { $0.frame.intersection(lastArea.rect) }
                .filter { !$0.isNull && $0.width >= 1 && $0.height >= 1 }
            guard !covered.isEmpty else {
                self.lastArea = nil
                throw SnapletError.displayDisconnected
            }

            // Keep the original rectangle when every part of it is still
            // visible; otherwise fall back to the part that is.
            let visible = covered.reduce(covered[0]) { $0.union($1) }
            let rect = visible.intersection(lastArea.rect)
            guard rect.width >= 2, rect.height >= 2 else {
                self.lastArea = nil
                throw SnapletError.displayDisconnected
            }

            guard let composed = MultiDisplayCompositor.composite(selection: rect, from: snapshots) else {
                throw SnapletError.captureFailed("the stored area is no longer on screen")
            }
            let displayID = snapshots.first { $0.frame.intersects(rect) }?.displayID ?? lastArea.displayID
            self.lastArea = LastArea(displayID: displayID, rect: rect)
            return CaptureResult(image: composed.image,
                                 scale: composed.scale,
                                 source: .area(displayID: displayID, rect: rect))
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
            overlay.confinesSelectionToOneDisplay = false
            let outcome = await overlay.present(mode: .area, snapshots: snapshots, candidates: [])
            guard case .area(let image, let scale, let rect, let displayID) = outcome else { return nil }
            lastArea = LastArea(displayID: displayID, rect: rect)
            return CaptureResult(image: image,
                                 scale: scale,
                                 source: .area(displayID: displayID, rect: rect))
        } catch {
            report(error)
            return nil
        }
    }

    /// Lets the user pick a region to record. Returns the display and the
    /// rectangle in global AppKit points.
    func selectRecordingArea() async -> (displayID: CGDirectDisplayID, rect: CGRect)? {
        guard !isBusy, await ensurePermission() else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let snapshots = try await screenshots.captureAllDisplays()
            // A capture stream is bound to one display, so a recording area
            // cannot span monitors the way a screenshot selection can.
            overlay.confinesSelectionToOneDisplay = true
            defer { overlay.confinesSelectionToOneDisplay = false }
            let outcome = await overlay.present(mode: .area, snapshots: snapshots, candidates: [])
            guard case .area(_, _, let rect, let displayID) = outcome,
                  rect.width >= 16, rect.height >= 16 else { return nil }
            return (displayID, rect)
        } catch {
            report(error)
            return nil
        }
    }

    /// Lets the user pick a window to record.
    func selectRecordingWindow() async -> CGWindowID? {
        guard !isBusy, await ensurePermission() else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let content = try await screenshots.shareableContent()
            let snapshots = try await screenshots.captureAllDisplays()
            let candidates = screenshots.windowCandidates(from: content, geometry: .current)
            guard !candidates.isEmpty else { throw SnapletError.noCaptureSource }
            let outcome = await overlay.present(mode: .window, snapshots: snapshots, candidates: candidates)
            guard case .window(let candidate) = outcome else { return nil }
            return candidate.scWindow.windowID
        } catch {
            report(error)
            return nil
        }
    }

    /// Counts down before capturing, so a menu or hover state can be opened
    /// first. Returns whether it actually waited.
    @discardableResult
    private func runCaptureDelay() async -> Bool {
        let seconds = SettingsStore.shared.preferences.captureDelaySeconds
        guard seconds > 0 else { return false }
        countdown.show(seconds: seconds)
        defer { countdown.hide() }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            countdown.update(remaining: remaining)
            try? await Task.sleep(for: .seconds(1))
        }
        return true
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
