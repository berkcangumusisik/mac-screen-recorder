import AVFoundation
import XCTest
@testable import Snaplet

/// Drives `RecordingWriter` with synthetic frames at the sizes real displays
/// produce. Screen capture needs a permission the test runner does not have,
/// but the writer is where recordings actually fail, and it can be exercised
/// directly.
final class RecordingWriterTests: XCTestCase {

    private var outputURL: URL!

    override func setUp() {
        super.setUp()
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-writer-\(UUID().uuidString).mp4")
    }

    override func tearDown() {
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        super.tearDown()
    }

    // MARK: - Synthetic media

    private func pixelBuffer(width: Int, height: Int, tint: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
                            &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, Int32(tint), CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    private func videoSample(width: Int, height: Int, frame: Int, frameRate: Int) -> CMSampleBuffer {
        let pixelBuffer = pixelBuffer(width: width, height: height, tint: UInt8(40 + frame % 60))
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate)),
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription!,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        return sampleBuffer!
    }

    private func videoSampleAt(_ time: CMTime, width: Int, height: Int) -> CMSampleBuffer {
        let pixelBuffer = pixelBuffer(width: width, height: height, tint: 90)
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription!,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        return sampleBuffer!
    }

    private func audioSample(at seconds: Double, frames: AVAudioFrameCount = 1024) -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 48_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = sin(Float(frame) * 0.05) * 0.2
            }
        }
        return AudioConversion.sampleBuffer(from: buffer,
                                            presentationTime: CMTime(seconds: seconds,
                                                                     preferredTimescale: 48_000))!
    }

    /// Feeds one second of video (and optionally audio) through the writer.
    @discardableResult
    private func record(width: Int,
                        height: Int,
                        frameRate: Int,
                        hasAudio: Bool,
                        frames: Int = 30) throws -> Result<URL, Error> {
        let writer = try RecordingWriter(outputURL: outputURL,
                                         videoSize: CGSize(width: width, height: height),
                                         frameRate: frameRate,
                                         hasAudio: hasAudio,
                                         needsPixelBufferInput: false)

        for frame in 0..<frames {
            // The encoder needs a moment on large frames; dropping them would
            // hide the very failure this test is looking for.
            var waited = 0
            while !writer.isReadyForVideo && waited < 2000 {
                usleep(1000)
                waited += 1
            }
            writer.appendVideo(videoSample(width: width, height: height,
                                           frame: frame, frameRate: frameRate))
            if hasAudio, frame % 2 == 0 {
                writer.appendAudio(audioSample(at: Double(frame) / Double(frameRate)))
            }
            if let failure = writer.failure {
                return .failure(failure)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!
        writer.finish { outcome in
            result = outcome
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }

    private func assertRecorded(width: Int, height: Int, frameRate: Int, hasAudio: Bool,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try record(width: width, height: height, frameRate: frameRate, hasAudio: hasAudio)
        switch result {
        case .success(let url):
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), file: file, line: line)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size ?? 0, 1000, "file is suspiciously small", file: file, line: line)
        case .failure(let error):
            XCTFail("\(width)x\(height) @\(frameRate) audio=\(hasAudio) failed: \(error)",
                    file: file, line: line)
        }
    }

    // MARK: - Real display geometries

    func testRecordsAnExternal1080pDisplay() throws {
        try assertRecorded(width: 1920, height: 1080, frameRate: 60, hasAudio: true)
    }

    /// A 1512x982 point Retina display captures at 3024x1964 — an odd size that
    /// is not a multiple of 16 in either direction.
    func testRecordsABuiltInRetinaDisplayAtFullResolution() throws {
        try assertRecorded(width: 3024, height: 1964, frameRate: 60, hasAudio: true)
    }

    func testRecordsWithoutAudio() throws {
        try assertRecorded(width: 1920, height: 1080, frameRate: 30, hasAudio: false)
    }

    func testRecordsATallOddSize() throws {
        try assertRecorded(width: 1170, height: 2532, frameRate: 30, hasAudio: false)
    }

    // MARK: - Input the capture stream really produces

    /// The system audio tap is already running when the first video frame
    /// arrives, so audio routinely turns up with a timestamp before the session
    /// starts. Appending it fails the whole writer, which used to end the
    /// recording with an unexplained write error.
    func testAudioFromBeforeTheFirstVideoFrameIsDroppedNotFatal() throws {
        let writer = try RecordingWriter(outputURL: outputURL,
                                         videoSize: CGSize(width: 640, height: 480),
                                         frameRate: 30,
                                         hasAudio: true,
                                         needsPixelBufferInput: false)

        // Video starts at 10 s on the host clock; audio has been running since 9 s.
        for early in stride(from: 9.0, to: 10.0, by: 0.1) {
            writer.appendAudio(audioSample(at: early))
        }
        for frame in 0..<20 {
            while !writer.isReadyForVideo { usleep(500) }
            let time = CMTime(seconds: 10 + Double(frame) / 30, preferredTimescale: 600)
            writer.appendVideo(videoSampleAt(time, width: 640, height: 480))
            writer.appendAudio(audioSample(at: 10 + Double(frame) / 30))
        }

        XCTAssertNil(writer.failure, "early audio must not fail the writer")
        XCTAssertGreaterThan(writer.droppedOutOfOrderSamples, 0, "early audio should have been dropped")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!
        writer.finish { result = $0; semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 30)

        switch result {
        case .success(let url):
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        case .failure(let error):
            XCTFail("recording should still finish: \(error)")
        case .none:
            XCTFail("finish timed out")
        }
    }

    /// A frame that does not advance the timeline fails the session outright.
    func testRepeatedOrRewoundTimestampsAreDroppedNotFatal() throws {
        let writer = try RecordingWriter(outputURL: outputURL,
                                         videoSize: CGSize(width: 640, height: 480),
                                         frameRate: 30,
                                         hasAudio: false,
                                         needsPixelBufferInput: false)

        let times = [0.0, 0.033, 0.033, 0.066, 0.050, 0.100]
        for seconds in times {
            while !writer.isReadyForVideo { usleep(500) }
            writer.appendVideo(videoSampleAt(CMTime(seconds: seconds, preferredTimescale: 600),
                                             width: 640, height: 480))
        }

        XCTAssertNil(writer.failure)
        // The duplicate 0.033 and the rewound 0.050 are the two that go.
        XCTAssertEqual(writer.droppedOutOfOrderSamples, 2)
        XCTAssertEqual(writer.appendedVideoFrames, 4)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!
        writer.finish { result = $0; semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 30)
        XCTAssertNotNil(try? result?.get())
    }

    func testWriteFailuresCarryTheDomainAndCode() {
        let underlying = NSError(domain: "SomeCodec", code: -12345)
        let error = NSError(domain: AVFoundationErrorDomain,
                            code: -11800,
                            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed",
                                       NSUnderlyingErrorKey: underlying])
        let described = RecordingWriter.describe(error)

        XCTAssertTrue(described.contains("-11800"), described)
        XCTAssertTrue(described.contains(AVFoundationErrorDomain), described)
        XCTAssertTrue(described.contains("SomeCodec"), described)
        XCTAssertTrue(described.contains("-12345"), described)
    }
}
