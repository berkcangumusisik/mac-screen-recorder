import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit

/// Bridges ScreenCaptureKit callbacks, which arrive on a background queue, into
/// plain closures.
final class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    var onScreen: ((CMSampleBuffer) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    var onMicrophone: ((CMSampleBuffer) -> Void)?
    var onStop: ((Error) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen: onScreen?(sampleBuffer)
        case .audio: onSystemAudio?(sampleBuffer)
        case .microphone: onMicrophone?(sampleBuffer)
        @unknown default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}

/// One recording, from stream setup to a finished file.
final class RecordingSession {

    let outputURL: URL
    private let configuration: RecordingConfiguration
    private let handler = StreamOutputHandler()
    private let processingQueue = DispatchQueue(label: "app.snaplet.recording.frames",
                                                qos: .userInitiated)
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var compositor: FrameCompositor?
    private var webcam: WebcamCapture?
    private var mixer: AudioMixer?
    private var isFinished = false

    /// Fired when the system, not the user, ends the recording.
    var onUnexpectedStop: ((SnapletError) -> Void)?

    private(set) var outputSize: CGSize = .zero

    /// The display this session is bound to, used to notice an unplugged monitor.
    var configurationDisplayID: CGDirectDisplayID? { configuration.target.displayID }

    init(configuration: RecordingConfiguration, outputURL: URL) {
        self.configuration = configuration
        self.outputURL = outputURL
    }

    // MARK: - Start

    @MainActor
    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SnapletError.screenRecordingPermissionDenied
        }

        let (filter, sourcePixelSize, sourceRect) = try resolveTarget(content: content)
        outputSize = configuration.outputSize(forSource: sourcePixelSize)

        guard DiskSpace.hasAtLeast(500_000_000, at: outputURL.deletingLastPathComponent()) else {
            throw SnapletError.diskFull
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = Int(outputSize.width)
        streamConfiguration.height = Int(outputSize.height)
        streamConfiguration.minimumFrameInterval = CMTime(value: 1,
                                                          timescale: CMTimeScale(configuration.frameRate))
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = configuration.showsCursor
        streamConfiguration.showMouseClicks = configuration.showsCursor && configuration.highlightsClicks
        streamConfiguration.queueDepth = 6
        streamConfiguration.preservesAspectRatio = true
        streamConfiguration.scalesToFit = false
        streamConfiguration.capturesAudio = configuration.capturesSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2
        streamConfiguration.captureMicrophone = configuration.capturesMicrophone
        if let sourceRect { streamConfiguration.sourceRect = sourceRect }

        // The webcam overlay means every frame has to be recomposited.
        if let overlay = configuration.webcam {
            let capture = WebcamCapture()
            do {
                try capture.start(deviceID: overlay.deviceID)
                webcam = capture
                compositor = FrameCompositor(outputSize: outputSize, overlay: overlay)
            } catch {
                Log.recording.error("Webcam unavailable, recording without overlay")
                throw error
            }
        }

        let hasAudio = configuration.capturesSystemAudio || configuration.capturesMicrophone
        let writer = try RecordingWriter(outputURL: outputURL,
                                         videoSize: outputSize,
                                         frameRate: configuration.frameRate,
                                         hasAudio: hasAudio,
                                         needsPixelBufferInput: compositor != nil)
        self.writer = writer

        if configuration.capturesSystemAudio && configuration.capturesMicrophone,
           let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 48_000,
                                      channels: 2,
                                      interleaved: false) {
            mixer = AudioMixer(format: format)
        }

        installHandlers()

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: handler)
        self.stream = stream
        do {
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: processingQueue)
            if configuration.capturesSystemAudio {
                try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: processingQueue)
            }
            if configuration.capturesMicrophone {
                try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: processingQueue)
            }
            try await stream.startCapture()
        } catch {
            await cleanUpAfterFailure()
            throw Self.mapped(error)
        }
    }

    @MainActor
    private func resolveTarget(content: SCShareableContent) throws
        -> (SCContentFilter, CGSize, CGRect?) {

        let ownApplication = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }

        switch configuration.target {
        case .display(let displayID), .area(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID }),
                  let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                throw SnapletError.displayDisconnected
            }
            let filter = SCContentFilter(display: display,
                                         excludingApplications: ownApplication.map { [$0] } ?? [],
                                         exceptingWindows: [])
            let scale = screen.backingScaleFactor
            if case .area(_, let rect) = configuration.target {
                let clipped = rect.intersection(screen.frame)
                guard clipped.width >= 16, clipped.height >= 16 else {
                    throw SnapletError.displayDisconnected
                }
                // sourceRect is display-local points with a top-left origin.
                let local = CGRect(x: clipped.minX - screen.frame.minX,
                                   y: screen.frame.maxY - clipped.maxY,
                                   width: clipped.width,
                                   height: clipped.height)
                return (filter,
                        CGSize(width: clipped.width * scale, height: clipped.height * scale),
                        local)
            }
            return (filter,
                    CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                    nil)

        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw SnapletError.targetDisappeared
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            return (filter,
                    CGSize(width: filter.contentRect.width * scale,
                           height: filter.contentRect.height * scale),
                    nil)
        }
    }

    // MARK: - Frame handling

    private func installHandlers() {
        handler.onScreen = { [weak self] sampleBuffer in
            self?.handleScreen(sampleBuffer)
        }
        handler.onStop = { [weak self] error in
            guard let self, !self.isFinished else { return }
            self.onUnexpectedStop?(Self.mapped(error))
        }

        let usesMixer = mixer != nil
        if configuration.capturesSystemAudio {
            handler.onSystemAudio = { [weak self] sampleBuffer in
                guard let self, let writer = self.writer else { return }
                if usesMixer, let mixed = self.mixer?.mix(primary: sampleBuffer) {
                    writer.appendAudio(mixed)
                } else {
                    writer.appendAudio(sampleBuffer)
                }
            }
        }
        if configuration.capturesMicrophone {
            handler.onMicrophone = { [weak self] sampleBuffer in
                guard let self else { return }
                if usesMixer {
                    self.mixer?.enqueueSecondary(sampleBuffer)
                } else {
                    self.writer?.appendAudio(sampleBuffer)
                }
            }
        }
    }

    private func handleScreen(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, Self.isComplete(sampleBuffer) else { return }

        if let compositor, let pool = writer.pixelBufferPool,
           let source = sampleBuffer.imageBuffer {
            var destination: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                  let destination else { return }
            compositor.composite(screen: source, camera: webcam?.latestFrame, into: destination)
            writer.appendVideo(pixelBuffer: destination, at: sampleBuffer.presentationTimeStamp)
        } else {
            writer.appendVideo(sampleBuffer)
        }

        if let failure = writer.failure, !isFinished {
            isFinished = true
            onUnexpectedStop?(failure)
        }
    }

    /// Skips the "idle" and "blank" frames ScreenCaptureKit emits when nothing
    /// on screen changed; their pixel data is not valid to encode.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                        createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    // MARK: - Stop

    /// Stops capture and finalises the file. Throws when nothing usable exists.
    func stop() async throws -> URL {
        isFinished = true
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        webcam?.stop()
        webcam = nil
        mixer?.reset()

        guard let writer else { throw SnapletError.recordingNotActive }
        defer { self.writer = nil }
        return try await writer.finish()
    }

    /// Best-effort finalisation for app termination, where awaiting is not an
    /// option. Returns whether a file was written within `timeout`.
    @discardableResult
    func stopSynchronously(timeout: TimeInterval = 5) -> URL? {
        isFinished = true
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        webcam?.stop()
        webcam = nil

        guard let writer else { return nil }
        self.writer = nil

        let semaphore = DispatchSemaphore(value: 0)
        var result: URL?
        writer.finish { outcome in
            result = try? outcome.get()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    private func cleanUpAfterFailure() async {
        webcam?.stop()
        webcam = nil
        writer?.cancel()
        writer = nil
        stream = nil
    }

    private static func mapped(_ error: Error) -> SnapletError {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            return .recordingSetupFailed(nsError.localizedDescription)
        }
        switch nsError.code {
        case -3801, -3803: return .screenRecordingPermissionDenied
        case -3804, -3805, -3806: return .targetDisappeared
        case -3817: return .recordingWriteFailed("stopped by the user")
        case -3820: return .microphonePermissionDenied
        case -3821: return .recordingWriteFailed("stopped by the system")
        default: return .recordingSetupFailed(nsError.localizedDescription)
        }
    }
}
