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
    private var isFinishing = false
    private var sessionStartTime: CMTime = .invalid
    private var lastVideoTime: CMTime = .invalid

    // Pausing keeps the file continuous: samples are dropped while paused, and
    // everything after resuming is shifted back by however long the pause
    // lasted, so the recording has no dead air and no frozen frame.
    private var isPaused = false
    private var pausedOffset: CMTime = .zero
    private var pauseStartedAt: CMTime = .invalid
    private var awaitingFirstFrameAfterResume = false
    private var lastSourceTime: CMTime = .invalid
    private(set) var droppedOutOfOrderSamples = 0
    private(set) var failure: SnapletError?
    private(set) var appendedVideoFrames = 0
    private(set) var appendedAudioBuffers = 0
    private var lastVideoFormat: String?
    private var lastAudioFormat: String?
    /// Every distinct video format seen. A capture stream is supposed to deliver
    /// one; more than one means the encoder was handed something it was not
    /// configured for.
    private var videoFormats: [String] = []

    var pixelBufferPool: CVPixelBufferPool? { pixelBufferAdaptor?.pixelBufferPool }

    /// Whether the encoder can accept another video frame right now.
    var isReadyForVideo: Bool { videoInput.isReadyForMoreMediaData }

    var isCurrentlyPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return isPaused
    }

    /// Total time spent paused, which is the amount the timeline was shortened by.
    var pausedDuration: CMTime {
        lock.lock(); defer { lock.unlock() }
        return pausedOffset
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            pauseStartedAt = lastSourceTime
        } else {
            // The offset cannot be computed until a frame actually arrives; the
            // gap is measured against the first one after resuming.
            awaitingFirstFrameAfterResume = pauseStartedAt.isValid
        }
    }

    /// Shifts a sample back by the accumulated pause time, so the written
    /// timeline is continuous.
    private func timeShifted(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        guard time.isValid else { return nil }
        var timing = CMSampleTimingInfo(duration: sampleBuffer.duration,
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var shifted: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                    sampleBuffer: sampleBuffer,
                                                    sampleTimingEntryCount: 1,
                                                    sampleTimingArray: &timing,
                                                    sampleBufferOut: &shifted) == noErr else {
            return nil
        }
        return shifted
    }

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
        // Deliberately no `movieFragmentInterval`.
        //
        // Fragmented output looked like a cheap way to survive a crash, but on
        // .mp4 it corrupts the recording: roughly two in five captures failed
        // shortly after the first fragment was flushed, with
        // AVFoundationErrorDomain -11800 / NSOSStatusErrorDomain -16341, and the
        // whole recording was lost. Disabling it made 5 of 5 succeed under the
        // same conditions. `LiveCaptureIntegrationTests` reproduces both sides.
        //
        // Snaplet still finalises an in-progress recording when the app is asked
        // to quit; what is gone is resilience against an outright crash.

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
        let sourceTime = sampleBuffer.presentationTimeStamp
        guard sourceTime.isValid else { return }

        lock.lock()
        lastSourceTime = sourceTime
        if isPaused {
            lock.unlock()
            return
        }
        if awaitingFirstFrameAfterResume, pauseStartedAt.isValid {
            // Leave one frame of spacing, otherwise the first frame after the
            // pause lands exactly on the last one written before it and the
            // monotonic guard drops it.
            let step = sampleBuffer.duration.isNumeric && sampleBuffer.duration > .zero
                ? sampleBuffer.duration
                : CMTime(value: 1, timescale: 600)
            let gap = (sourceTime - pauseStartedAt) - step
            if gap > .zero { pausedOffset = pausedOffset + gap }
            awaitingFirstFrameAfterResume = false
            pauseStartedAt = .invalid
        }
        let offset = pausedOffset
        lock.unlock()

        let time = sourceTime - offset
        guard let sampleBuffer = offset == .zero ? sampleBuffer
                : timeShifted(sampleBuffer, to: time) else { return }
        // AVAssetWriter tolerates a repeated or rewound timestamp, but the
        // resulting file confuses players and breaks the trimming maths in the
        // video editor, which assumes a monotonic timeline.
        guard !lastVideoTime.isValid || time > lastVideoTime else {
            droppedOutOfOrderSamples += 1
            return
        }
        startSessionIfNeeded(at: time)
        guard videoInput.isReadyForMoreMediaData else { return }
        let format = Self.describeFormat(sampleBuffer)
        if lastVideoFormat == nil { lastVideoFormat = format }
        if !videoFormats.contains(format) { videoFormats.append(format) }
        if videoInput.append(sampleBuffer) {
            lastVideoTime = time
            appendedVideoFrames += 1
        }
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, at sourceTime: CMTime) {
        guard checkWriterHealth(), let pixelBufferAdaptor else { return }
        guard sourceTime.isValid else { return }

        lock.lock()
        lastSourceTime = sourceTime
        if isPaused {
            lock.unlock()
            return
        }
        if awaitingFirstFrameAfterResume, pauseStartedAt.isValid {
            // Same one-frame spacing as the sample-buffer path above.
            let gap = (sourceTime - pauseStartedAt) - CMTime(value: 1, timescale: 600)
            if gap > .zero { pausedOffset = pausedOffset + gap }
            awaitingFirstFrameAfterResume = false
            pauseStartedAt = .invalid
        }
        let offset = pausedOffset
        lock.unlock()

        let time = sourceTime - offset
        guard !lastVideoTime.isValid || time > lastVideoTime else {
            droppedOutOfOrderSamples += 1
            return
        }
        startSessionIfNeeded(at: time)
        guard videoInput.isReadyForMoreMediaData else { return }
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time) {
            lastVideoTime = time
            appendedVideoFrames += 1
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard checkWriterHealth(), let audioInput else { return }
        // Audio before the first video frame has nowhere to go. AVFoundation
        // would trim a sample stamped before the session, but dropping it here
        // keeps the two tracks starting at the same instant.
        guard didStartSession, sessionStartTime.isValid else { return }

        lock.lock()
        let paused = isPaused
        let offset = pausedOffset
        lock.unlock()
        guard !paused else { return }

        let time = sampleBuffer.presentationTimeStamp - offset
        guard time.isValid, time >= sessionStartTime else {
            droppedOutOfOrderSamples += 1
            return
        }
        guard let sampleBuffer = offset == .zero ? sampleBuffer
                : timeShifted(sampleBuffer, to: time) else { return }
        guard audioInput.isReadyForMoreMediaData else { return }
        if lastAudioFormat == nil { lastAudioFormat = Self.describeFormat(sampleBuffer) }
        if audioInput.append(sampleBuffer) {
            appendedAudioBuffers += 1
        }
    }

    private func startSessionIfNeeded(at time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !didStartSession else { return }
        writer.startSession(atSourceTime: time)
        sessionStartTime = time
        didStartSession = true
    }

    private func checkWriterHealth() -> Bool {
        // Capture callbacks arrive on their own queue and can still be in
        // flight when finishing starts. Appending during finishWriting is not
        // defined, so close the door before it can happen.
        lock.lock()
        let finishing = isFinishing
        lock.unlock()
        guard !finishing else { return false }

        guard failure == nil else { return false }
        guard writer.status != .failed else {
            // Which track was actually carrying data, and in what format, is the
            // difference between a diagnosable report and "it broke".
            let mapped = Self.mapped(writer.error)
            if case .recordingWriteFailed(let detail) = mapped {
                failure = .recordingWriteFailed("\(detail) · \(diagnosticSummary)")
            } else {
                failure = mapped
            }
            Log.recording.error("Writer failed: \(self.diagnosticSummary, privacy: .public)")
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
        lock.lock()
        isFinishing = true
        lock.unlock()

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
                let mapped = Self.mapped(self.writer.error)
                if case .recordingWriteFailed(let detail) = mapped {
                    completion(.failure(SnapletError.recordingWriteFailed(
                        "\(detail) · \(self.diagnosticSummary)")))
                } else {
                    completion(.failure(mapped))
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        isFinishing = true
        lock.unlock()
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: outputURL)
    }

    /// What the writer had actually accepted when it failed.
    var diagnosticSummary: String {
        var parts = ["video \(appendedVideoFrames)×\(lastVideoFormat ?? "no frames")"]
        if videoFormats.count > 1 {
            parts.append("FORMAT CHANGED: \(videoFormats.joined(separator: " -> "))")
        }
        if audioInput != nil {
            parts.append("audio \(appendedAudioBuffers)×\(lastAudioFormat ?? "no buffers")")
        } else {
            parts.append("audio off")
        }
        if droppedOutOfOrderSamples > 0 {
            parts.append("dropped \(droppedOutOfOrderSamples)")
        }
        return parts.joined(separator: " · ")
    }

    /// Compact, non-identifying description of a sample buffer's format.
    static func describeFormat(_ sampleBuffer: CMSampleBuffer) -> String {
        guard let description = sampleBuffer.formatDescription else { return "unknown" }
        switch description.mediaType {
        case .video:
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let subType = description.mediaSubType.rawValue
            return "\(dimensions.width)x\(dimensions.height)/\(fourCharCode(subType))"
        case .audio:
            guard let asbd = description.audioStreamBasicDescription else { return "audio?" }
            return "\(Int(asbd.mSampleRate))Hz/\(asbd.mChannelsPerFrame)ch/"
                + "\(asbd.mBitsPerChannel)bit/flags\(asbd.mFormatFlags)"
        default:
            return "other"
        }
    }

    private static func fourCharCode(_ value: FourCharCode) -> String {
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                     UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        let text = String(bytes: bytes, encoding: .ascii) ?? "?"
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// AVFoundation often reports only "the operation could not be completed",
    /// which is useless in a bug report. Carry the domain, the code and any
    /// underlying error through to the message the user sees.
    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "unknown error" }
        var parts = [error.localizedDescription, "\(error.domain) \(error.code)"]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying \(underlying.domain) \(underlying.code)")
        }
        if let reason = error.localizedFailureReason {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    private static func mapped(_ error: Error?) -> SnapletError {
        guard let error = error as NSError? else { return .recordingWriteFailed("unknown error") }
        if error.code == NSFileWriteOutOfSpaceError ||
            (error.underlyingErrors.contains { ($0 as NSError).code == NSFileWriteOutOfSpaceError }) {
            return .diskFull
        }
        return .recordingWriteFailed(describe(error))
    }
}
