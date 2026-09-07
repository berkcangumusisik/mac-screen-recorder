import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Cancellable MP4 and GIF export driven by the same `VideoEdit` as the preview.
@MainActor
final class VideoExporter: ObservableObject {

    @Published private(set) var progress: Double = 0
    @Published private(set) var isExporting = false
    @Published private(set) var statusText: String = ""

    private var cancelFlag = CancellationFlag()

    func cancel() {
        cancelFlag.cancel()
    }

    // MARK: - MP4

    func exportMovie(asset: AVAsset,
                     edit: VideoEdit,
                     sourceSize: CGSize,
                     frameRate: Int,
                     to url: URL) async throws -> URL {
        guard !isExporting else { throw SnapletError.exportFailed("an export is already running") }
        isExporting = true
        progress = 0
        statusText = String(localized: "Preparing…")
        cancelFlag = CancellationFlag()
        defer { isExporting = false }

        let (composition, renderSize) = try await VideoCompositionBuilder.make(asset: asset,
                                                                               edit: edit,
                                                                               sourceSize: sourceSize,
                                                                               frameRate: frameRate)
        let range = CMTimeRange(start: CMTime(seconds: edit.trimStart, preferredTimescale: 600),
                                duration: CMTime(seconds: edit.trimmedDuration, preferredTimescale: 600))
        guard range.duration.seconds > 0.05 else {
            throw SnapletError.exportFailed("the selected range is empty")
        }

        statusText = String(localized: "Exporting video…")
        let flag = cancelFlag
        let start = ContinuousClock.now
        let result = try await Task.detached(priority: .userInitiated) {
            try MovieWriterPipeline.run(asset: asset,
                                        composition: composition,
                                        renderSize: renderSize,
                                        frameRate: frameRate,
                                        timeRange: range,
                                        outputURL: url,
                                        cancelFlag: flag) { fraction in
                Task { @MainActor [weak self] in self?.progress = fraction }
            }
        }.value

        Metrics.shared.record(MetricName.videoExport, duration: start.secondsElapsed)
        progress = 1
        return result
    }

    // MARK: - GIF

    func exportGIF(asset: AVAsset,
                   edit: VideoEdit,
                   sourceSize: CGSize,
                   options: GIFExportOptions,
                   to url: URL) async throws -> URL {
        guard !isExporting else { throw SnapletError.exportFailed("an export is already running") }
        isExporting = true
        progress = 0
        statusText = String(localized: "Rendering frames…")
        cancelFlag = CancellationFlag()
        defer { isExporting = false }

        let (start, end) = GIFExportOptions.clampedRange(start: edit.trimStart, end: edit.trimEnd)
        let duration = end - start
        let frameCount = max(2, Int(duration * Double(options.frameRate)))

        let (composition, renderSize) = try await VideoCompositionBuilder.make(asset: asset,
                                                                               edit: edit,
                                                                               sourceSize: sourceSize,
                                                                               frameRate: options.frameRate)
        let scale = min(1, CGFloat(options.maximumWidth) / renderSize.width)
        let outputSize = CGSize(width: (renderSize.width * scale).rounded(),
                                height: (renderSize.height * scale).rounded())

        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = outputSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5 / Double(options.frameRate),
                                                       preferredTimescale: 600)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.gif.identifier as CFString,
                                                                frameCount,
                                                                nil) else {
            throw SnapletError.exportFailed("could not create the GIF file")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / Double(options.frameRate),
                kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(options.frameRate)
            ]
        ] as CFDictionary

        var written = 0
        for index in 0..<frameCount {
            if cancelFlag.isCancelled {
                try? FileManager.default.removeItem(at: url)
                throw SnapletError.exportCancelled
            }
            let time = CMTime(seconds: start + duration * Double(index) / Double(frameCount),
                              preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                CGImageDestinationAddImage(destination, image, frameProperties)
                written += 1
            } catch {
                Log.export.debug("Skipped GIF frame at \(time.seconds, privacy: .public)s")
            }
            progress = Double(index + 1) / Double(frameCount)
        }

        guard written > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw SnapletError.exportFailed("no frames could be rendered")
        }
        progress = 1
        return url
    }
}

/// Thread-safe cancellation shared with the background export pipeline.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Reader/writer pump. Using AVAssetReader rather than AVAssetExportSession
/// gives exact control over the output size, real progress and a cancel that
/// takes effect immediately.
enum MovieWriterPipeline {

    static func run(asset: AVAsset,
                    composition: AVVideoComposition,
                    renderSize: CGSize,
                    frameRate: Int,
                    timeRange: CMTimeRange,
                    outputURL: URL,
                    cancelFlag: CancellationFlag,
                    onProgress: @escaping (Double) -> Void) throws -> URL {

        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let videoTracks = loadTracksSynchronously(asset: asset, mediaType: .video)
        guard !videoTracks.isEmpty else { throw SnapletError.exportFailed("no video track") }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw SnapletError.exportFailed("video output rejected") }
        reader.add(videoOutput)

        let audioTracks = loadTracksSynchronously(asset: asset, mediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let pixels = Double(renderSize.width * renderSize.height)
        let bitrate = Int(min(60_000_000, max(2_000_000, pixels * Double(frameRate) * 0.09)))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: max(30, frameRate * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw SnapletError.exportFailed("video input rejected") }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            throw SnapletError.exportFailed(writer.error?.localizedDescription
                                            ?? reader.error?.localizedDescription
                                            ?? "could not start")
        }
        writer.startSession(atSourceTime: timeRange.start)

        let group = DispatchGroup()
        let duration = max(0.001, timeRange.duration.seconds)
        let startSeconds = timeRange.start.seconds
        var didCancel = false

        group.enter()
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "app.snaplet.export.video")) {
            while videoInput.isReadyForMoreMediaData {
                if cancelFlag.isCancelled {
                    didCancel = true
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                let time = sampleBuffer.presentationTimeStamp.seconds
                videoInput.append(sampleBuffer)
                onProgress(min(1, max(0, (time - startSeconds) / duration)))
            }
        }

        if let audioInput, let audioOutput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "app.snaplet.export.audio")) {
                while audioInput.isReadyForMoreMediaData {
                    if cancelFlag.isCancelled {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    audioInput.append(sampleBuffer)
                }
            }
        }

        group.wait()

        if didCancel || cancelFlag.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw SnapletError.exportCancelled
        }

        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw SnapletError.exportFailed(reader.error?.localizedDescription ?? "read failed")
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            let error = writer.error as NSError?
            if error?.code == NSFileWriteOutOfSpaceError { throw SnapletError.diskFull }
            throw SnapletError.exportFailed(error?.localizedDescription ?? "write failed")
        }
        onProgress(1)
        return outputURL
    }

    /// AVAssetReader outputs need tracks up front; the async loader cannot be
    /// used from inside the synchronous pipeline.
    private static func loadTracksSynchronously(asset: AVAsset, mediaType: AVMediaType) -> [AVAssetTrack] {
        let semaphore = DispatchSemaphore(value: 0)
        var tracks: [AVAssetTrack] = []
        Task {
            tracks = (try? await asset.loadTracks(withMediaType: mediaType)) ?? []
            semaphore.signal()
        }
        semaphore.wait()
        return tracks
    }
}
