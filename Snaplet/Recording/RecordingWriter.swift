import AVFoundation
import CoreMedia

/// Streams video and audio to disk as they arrive.
///
/// Nothing is buffered in memory beyond what AVFoundation needs, and movie
/// fragments are flushed periodically so an interrupted recording still leaves
/// a playable file behind.
final class RecordingWriter {

    let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()

    private var didStartSession = false
    private var lastVideoTime: CMTime = .invalid
    private(set) var failure: SnapletError?
    private(set) var appendedVideoFrames = 0

    var pixelBufferPool: CVPixelBufferPool? { pixelBufferAdaptor?.pixelBufferPool }

    init(outputURL: URL,
         videoSize: CGSize,
         frameRate: Int,
         hasAudio: Bool,
         needsPixelBufferInput: Bool) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw SnapletError.recordingSetupFailed(error.localizedDescription)
        }
        // Flush a fragment every two seconds: if the app is killed mid-recording
        // everything up to the last fragment is still readable.
        writer.movieFragmentInterval = CMTime(value: 2, timescale: 1)

        let width = Int(videoSize.width)
        let height = Int(videoSize.height)
        let pixels = Double(width * height)
        let bitrate = Int(min(60_000_000, max(2_000_000, pixels * Double(frameRate) * 0.09)))

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: max(30, frameRate * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true

        if needsPixelBufferInput {
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
        } else {
            pixelBufferAdaptor = nil
        }

        if hasAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.canAdd(videoInput) else {
            throw SnapletError.recordingSetupFailed("video input rejected")
        }
        writer.add(videoInput)
        if let audioInput, writer.canAdd(audioInput) { writer.add(audioInput) }

        guard writer.startWriting() else {
            throw SnapletError.recordingSetupFailed(writer.error?.localizedDescription ?? "writer refused to start")
        }
    }

    // MARK: - Appending

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard checkWriterHealth() else { return }
        let time = sampleBuffer.presentationTimeStamp
        guard time.isValid else { return }
        startSessionIfNeeded(at: time)
        guard videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sampleBuffer) {
            lastVideoTime = time
            appendedVideoFrames += 1
        }
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard checkWriterHealth(), let pixelBufferAdaptor else { return }
        guard time.isValid else { return }
        startSessionIfNeeded(at: time)
        guard videoInput.isReadyForMoreMediaData else { return }
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time) {
            lastVideoTime = time
            appendedVideoFrames += 1
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard checkWriterHealth(), let audioInput else { return }
        // Audio before the first video frame has nowhere to go.
        guard didStartSession, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    private func startSessionIfNeeded(at time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !didStartSession else { return }
        writer.startSession(atSourceTime: time)
        didStartSession = true
    }

    private func checkWriterHealth() -> Bool {
        guard failure == nil else { return false }
        guard writer.status != .failed else {
            failure = Self.mapped(writer.error)
            Log.recording.error("Writer failed: \(self.writer.error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        }
        return writer.status == .writing
    }

    // MARK: - Finishing

    /// Returns the finished file, or throws when nothing usable was written.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            finish { continuation.resume(with: $0) }
        }
    }

    /// Completion-based variant, used on app termination where there is no
    /// opportunity to await.
    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        guard writer.status == .writing else {
            completion(.failure(failure ?? .recordingWriteFailed("writer was not running")))
            return
        }
        guard didStartSession, appendedVideoFrames > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(SnapletError.recordingWriteFailed("no frames were captured")))
            return
        }
        if lastVideoTime.isValid {
            writer.endSession(atSourceTime: lastVideoTime)
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL
        writer.finishWriting { [weak self] in
            guard let self else { return }
            if self.writer.status == .completed {
                completion(.success(url))
            } else {
                completion(.failure(Self.mapped(self.writer.error)))
            }
        }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private static func mapped(_ error: Error?) -> SnapletError {
        guard let error = error as NSError? else { return .recordingWriteFailed("unknown error") }
        if error.code == NSFileWriteOutOfSpaceError ||
            (error.underlyingErrors.contains { ($0 as NSError).code == NSFileWriteOutOfSpaceError }) {
            return .diskFull
        }
        return .recordingWriteFailed(error.localizedDescription)
    }
}
