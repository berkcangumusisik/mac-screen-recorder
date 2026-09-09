import AVFoundation
import AppKit

/// Owns the recording lifecycle: target selection, countdown, the on-screen
/// control, the state machine and every way a recording can end.
@MainActor
final class RecordingPresenter: ObservableObject {

    enum TargetKind: String {
        case screen, area, window
    }

    private unowned let environment: AppEnvironment
    private let control = RecordingControlWindow()
    private let countdown = CountdownOverlay()

    @Published private(set) var state: RecordingState = .idle

    private var session: RecordingSession?
    private var ticker: Timer?
    private var countdownTask: Task<Void, Never>?
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: Date?
    private var lastTarget: TargetKind = .screen
    private var observers: [NSObjectProtocol] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        installSystemObservers()
    }

    var isActive: Bool { state.isActive }

    var menuTitle: String {
        state.respondsToStop
            ? String(localized: "Stop Recording")
            : String(localized: "Start Recording")
    }

    var canPause: Bool { state.canPause || state.isPaused }

    var pauseMenuTitle: String {
        state.isPaused ? String(localized: "Resume Recording") : String(localized: "Pause Recording")
    }

    /// Pausing keeps the file open; the timeline simply skips the gap.
    func togglePause() {
        switch state {
        case .recording:
            guard state.canTransition(to: .paused(since: Date())) else { return }
            session?.setPaused(true)
            pausedAt = Date()
            state = .paused(since: Date())
            control.update(elapsed: elapsedSeconds, isCountingDown: false, countdown: 0, isPaused: true)
        case .paused:
            guard let startedAt else { return }
            session?.setPaused(false)
            if let pausedAt { pausedAccumulated += Date().timeIntervalSince(pausedAt) }
            pausedAt = nil
            state = .recording(startedAt: startedAt)
        default:
            return
        }
        environment.menuBar?.setRecordingIndicator(TimeFormatting.clock(elapsedSeconds))
    }

    /// Wall-clock time actually recorded, with pauses taken out.
    private var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        let paused = pausedAccumulated + (pausedAt.map { Date().timeIntervalSince($0) } ?? 0)
        return max(0, Date().timeIntervalSince(startedAt) - paused)
    }

    // MARK: - Entry points

    func toggle() {
        if state.respondsToStop {
            stop(reason: .user)
        } else {
            start(kind: lastTarget)
        }
    }

    func start(kind: TargetKind) {
        guard case .idle = state else {
            if state.respondsToStop { stop(reason: .user) }
            return
        }
        lastTarget = kind
        transition(to: .preparing)
        Task { await beginSession(kind: kind) }
    }

    // MARK: - Session

    private func beginSession(kind: TargetKind) async {
        guard await PermissionsService.shared.ensureScreenRecording() else {
            fail(.screenRecordingPermissionDenied)
            return
        }

        let preferences = environment.settings.preferences

        if preferences.recordMicrophone, !(await PermissionsService.shared.ensureMicrophone()) {
            fail(.microphonePermissionDenied)
            return
        }
        if preferences.webcamEnabled, !(await PermissionsService.shared.ensureCamera()) {
            fail(.cameraPermissionDenied)
            return
        }

        guard let target = await resolveTarget(kind: kind) else {
            transition(to: .idle)
            return
        }

        var configuration = RecordingConfiguration(target: target)
        configuration.frameRate = preferences.videoFrameRate
        configuration.resolutionCap = preferences.resolutionCap
        configuration.capturesSystemAudio = preferences.recordSystemAudio
        configuration.capturesMicrophone = preferences.recordMicrophone
        configuration.showsCursor = preferences.showCursorInRecording
        configuration.highlightsClicks = preferences.highlightMouseClicks
        configuration.countdownSeconds = preferences.countdownSeconds
        if preferences.webcamEnabled {
            configuration.webcam = WebcamOverlayConfiguration(deviceID: preferences.webcamDeviceID,
                                                              shape: preferences.webcamShape,
                                                              corner: preferences.webcamCorner,
                                                              sizeFraction: preferences.webcamSizePercent)
        }

        if configuration.countdownSeconds > 0 {
            let cancelled = await runCountdown(configuration.countdownSeconds)
            if cancelled { return }
        }

        let directory = environment.settings.ensureOutputDirectory()
        let url = OutputNaming.uniqueURL(in: directory,
                                         fileName: OutputNaming.fileName(prefix: "Snaplet",
                                                                         date: Date(),
                                                                         fileExtension: "mp4"))
        let session = RecordingSession(configuration: configuration, outputURL: url)
        session.onUnexpectedStop = { [weak self] error in
            Task { @MainActor in self?.handleUnexpectedStop(error) }
        }
        self.session = session

        do {
            try await session.start()
        } catch {
            self.session = nil
            fail((error as? SnapletError) ?? .recordingSetupFailed(error.localizedDescription))
            return
        }

        startedAt = Date()
        transition(to: .recording(startedAt: startedAt ?? Date()))
        control.show()
        control.onStop = { [weak self] in self?.stop(reason: .user) }
        control.onTogglePause = { [weak self] in self?.togglePause() }
        startTicker()
    }

    private func resolveTarget(kind: TargetKind) async -> RecordingConfiguration.Target? {
        switch kind {
        case .screen:
            guard let screen = NSScreen.screenUnderMouse ?? NSScreen.main,
                  let displayID = screen.displayID else { return nil }
            return .display(displayID)
        case .area:
            guard let selection = await environment.captureCoordinator.selectRecordingArea() else { return nil }
            return .area(displayID: selection.displayID, rect: selection.rect)
        case .window:
            guard let windowID = await environment.captureCoordinator.selectRecordingWindow() else { return nil }
            return .window(windowID)
        }
    }

    /// Returns `true` when the user cancelled during the countdown.
    private func runCountdown(_ seconds: Int) async -> Bool {
        transition(to: .countingDown(remaining: seconds))
        countdown.show(seconds: seconds)
        control.show()
        control.onStop = { [weak self] in self?.stop(reason: .user) }

        for remaining in stride(from: seconds, through: 1, by: -1) {
            guard case .countingDown = state else {
                countdown.hide()
                return true
            }
            transition(to: .countingDown(remaining: remaining))
            countdown.update(remaining: remaining)
            control.update(elapsed: 0, isCountingDown: true, countdown: remaining)
            try? await Task.sleep(for: .seconds(1))
        }
        countdown.hide()
        guard case .countingDown = state else { return true }
        return false
    }

    // MARK: - Stopping

    private enum StopReason {
        case user
        case system(SnapletError)
    }

    private func stop(reason: StopReason) {
        switch state {
        case .paused:
            session?.setPaused(false)
        case .countingDown:
            // Cancel before anything was captured.
            countdownTask?.cancel()
            countdown.hide()
            control.hide()
            transition(to: .idle)
            environment.menuBar?.setRecordingIndicator(nil)
            return
        case .recording:
            break
        default:
            return
        }
        pausedAt = nil

        transition(to: .stopping)
        stopTicker()
        control.hide()
        countdown.hide()
        environment.menuBar?.setRecordingIndicator(nil)

        guard let session else {
            transition(to: .idle)
            return
        }
        self.session = nil
        transition(to: .finalizing)

        Task {
            do {
                let url = try await session.stop()
                transition(to: .idle)
                await finishRecording(at: url)
                if case .system(let error) = reason {
                    ErrorPresenter.present(error)
                }
            } catch {
                transition(to: .idle)
                let mapped = (error as? SnapletError) ?? .recordingWriteFailed(error.localizedDescription)
                Log.recording.error("Recording could not be finalised: \(mapped.localizedDescription, privacy: .public)")
                ErrorPresenter.present(mapped)
            }
        }
    }

    private func handleUnexpectedStop(_ error: SnapletError) {
        guard state.isRecording || state.isActive else { return }
        Log.recording.notice("Recording ended by the system: \(error.localizedDescription, privacy: .public)")
        stop(reason: .system(error))
    }

    /// Only called once the file is closed and readable — never before.
    private func finishRecording(at url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ErrorPresenter.present(.recordingWriteFailed("the file disappeared"))
            return
        }
        let poster = await VideoThumbnail.firstFrame(of: url)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = poster ?? TransparentImage.make(width: 640, height: 360)
        let result = CaptureResult(image: image, scale: scale, source: .importedFile(url))
        let pending = PendingCapture(result: result, savedURL: url, kind: .video)

        environment.library.record(url: url,
                                  kind: .video,
                                  pixelSize: CGSize(width: image.width, height: image.height),
                                  capturedAt: Date(),
                                  image: poster)

        if environment.settings.preferences.playCaptureSound {
            NSSound(named: "Tink")?.play()
        }
        if environment.settings.preferences.showPreviewPanel {
            environment.previewController.show(pending, autoDismissAfter: 12)
        }
    }

    // MARK: - Termination and system events

    /// Called from `applicationWillTerminate`; there is no time to await.
    func finalizeForTermination() {
        guard state.isActive, let session else { return }
        self.session = nil
        stopTicker()
        control.hide()
        countdown.hide()
        if let url = session.stopSynchronously() {
            Log.recording.notice("Saved in-progress recording during termination")
            environment.library.record(url: url,
                                      kind: .video,
                                      pixelSize: .zero,
                                      capturedAt: Date(),
                                      image: nil)
        }
        state = .idle
    }

    private func installSystemObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyTargetStillExists() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isRecording else { return }
                Log.recording.notice("Stopping recording because the Mac is going to sleep")
                self.stop(reason: .user)
            }
        })
    }

    /// A display being unplugged mid-recording ends the session cleanly rather
    /// than leaving a stream pointed at nothing.
    private func verifyTargetStillExists() {
        guard state.isRecording, let session else { return }
        guard let displayID = session.targetDisplayID else { return }
        let stillConnected = NSScreen.screens.contains { $0.displayID == displayID }
        if !stillConnected {
            stop(reason: .system(.displayDisconnected))
        }
    }

    // MARK: - Ticker

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.startedAt != nil else { return }
                let elapsed = self.elapsedSeconds
                self.control.update(elapsed: elapsed,
                                    isCountingDown: false,
                                    countdown: 0,
                                    isPaused: self.state.isPaused)
                self.environment.menuBar?.setRecordingIndicator(TimeFormatting.clock(elapsed))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
        pausedAccumulated = 0
        pausedAt = nil
    }

    // MARK: - State

    private func transition(to next: RecordingState) {
        guard state.canTransition(to: next) else {
            Log.recording.error("Rejected transition \(String(describing: self.state), privacy: .public) → \(String(describing: next), privacy: .public)")
            return
        }
        state = next
    }

    private func fail(_ error: SnapletError) {
        state = .failed(error)
        control.hide()
        countdown.hide()
        stopTicker()
        environment.menuBar?.setRecordingIndicator(nil)
        session = nil
        state = .idle
        ErrorPresenter.present(error)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

extension RecordingSession {
    var targetDisplayID: CGDirectDisplayID? { configurationDisplayID }
}

enum TransparentImage {
    static func make(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.darkGray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

enum VideoThumbnail {
    /// Poster frame for the preview panel and the history list.
    static func firstFrame(of url: URL, at seconds: Double = 0.1) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return image
        } catch {
            Log.recording.debug("Poster frame unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
