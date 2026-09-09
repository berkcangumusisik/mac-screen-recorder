import AVFoundation
import XCTest
@testable import Snaplet

final class RecordingStateTests: XCTestCase {

    func testIdleOnlyStartsThroughPreparing() {
        XCTAssertTrue(RecordingState.idle.canTransition(to: .preparing))
        XCTAssertFalse(RecordingState.idle.canTransition(to: .recording(startedAt: Date())))
        XCTAssertFalse(RecordingState.idle.canTransition(to: .stopping))
    }

    func testASecondStartWhileRecordingIsRejected() {
        let recording = RecordingState.recording(startedAt: Date())
        XCTAssertFalse(recording.canTransition(to: .preparing))
        XCTAssertFalse(recording.canTransition(to: .recording(startedAt: Date())))
        XCTAssertTrue(recording.canTransition(to: .stopping))
    }

    func testFinalisationIsTheNormalRouteBackToIdle() {
        XCTAssertTrue(RecordingState.stopping.canTransition(to: .finalizing))
        XCTAssertTrue(RecordingState.finalizing.canTransition(to: .idle))
    }

    /// A live recording owns an open file, so it must never be abandoned — it
    /// has to be stopped and finalised so the file is closed properly.
    func testALiveRecordingCannotJumpStraightToIdle() {
        XCTAssertFalse(RecordingState.recording(startedAt: Date()).canTransition(to: .idle))
        XCTAssertFalse(RecordingState.recording(startedAt: Date()).canTransition(to: .finalizing))
    }

    func testFailureIsReachableFromEveryStateAndRecoverable() {
        let states: [RecordingState] = [.idle, .preparing, .countingDown(remaining: 3),
                                        .recording(startedAt: Date()), .stopping, .finalizing]
        for state in states {
            XCTAssertTrue(state.canTransition(to: .failed(.diskFull)), "\(state) should be able to fail")
        }
        XCTAssertTrue(RecordingState.failed(.diskFull).canTransition(to: .idle))
    }

    /// Cancelling before anything is captured has to reach .idle. When it
    /// could not, the presenter stayed outside .idle and silently ignored every
    /// later start request — recording appeared to stop working entirely.
    func testAbandoningBeforeCaptureReturnsToIdle() {
        XCTAssertTrue(RecordingState.preparing.canTransition(to: .idle),
                      "a cancelled area or window picker must release the presenter")
        XCTAssertTrue(RecordingState.countingDown(remaining: 2).canTransition(to: .idle),
                      "cancelling during the countdown must release the presenter")
        XCTAssertTrue(RecordingState.stopping.canTransition(to: .idle),
                      "stopping with nothing to finalise must release the presenter")
    }

    func testEveryStateCanReachIdleWithoutGettingStuck() {
        let states: [RecordingState] = [.idle, .preparing, .countingDown(remaining: 3),
                                        .recording(startedAt: Date()), .stopping,
                                        .finalizing, .failed(.diskFull)]
        for state in states {
            let direct = state.canTransition(to: .idle)
            let viaStopping = state.canTransition(to: .stopping)
                && RecordingState.stopping.canTransition(to: .idle)
            XCTAssertTrue(direct || viaStopping,
                          "\(state) has no way back to idle, so recording would lock up")
        }
    }

    func testPausingIsOnlyPossibleWhileRecording() {
        XCTAssertTrue(RecordingState.recording(startedAt: Date()).canPause)
        XCTAssertFalse(RecordingState.countingDown(remaining: 2).canPause)
        XCTAssertFalse(RecordingState.idle.canPause)
        XCTAssertFalse(RecordingState.finalizing.canPause)
    }

    func testAPausedRecordingCanResumeOrStopButNotRestart() {
        let paused = RecordingState.paused(since: Date())
        XCTAssertTrue(paused.canTransition(to: .recording(startedAt: Date())))
        XCTAssertTrue(paused.canTransition(to: .stopping))
        XCTAssertFalse(paused.canTransition(to: .preparing))
        XCTAssertFalse(paused.canTransition(to: .idle),
                       "a paused recording still owns an open file")
        XCTAssertTrue(paused.respondsToStop)
    }

    func testStopRespondsOnlyWhileSomethingIsRunning() {
        XCTAssertTrue(RecordingState.recording(startedAt: Date()).respondsToStop)
        XCTAssertTrue(RecordingState.countingDown(remaining: 2).respondsToStop)
        XCTAssertFalse(RecordingState.preparing.respondsToStop)
        XCTAssertFalse(RecordingState.idle.respondsToStop)
    }
}

final class RecordingConfigurationTests: XCTestCase {

    private func configuration(cap: ResolutionCap) -> RecordingConfiguration {
        var configuration = RecordingConfiguration(target: .display(1))
        configuration.resolutionCap = cap
        return configuration
    }

    func testOriginalResolutionIsKeptExceptForEvenRounding() {
        let size = configuration(cap: .original).outputSize(forSource: CGSize(width: 2560, height: 1600))
        XCTAssertEqual(size, CGSize(width: 2560, height: 1600))
    }

    func testSmallSourcesAreNeverUpscaled() {
        let size = configuration(cap: .p2160).outputSize(forSource: CGSize(width: 800, height: 600))
        XCTAssertEqual(size, CGSize(width: 800, height: 600))
    }

    func testCapAppliesToTheLongestEdgeAndKeepsTheAspectRatio() {
        let source = CGSize(width: 3840, height: 2160)
        let size = configuration(cap: .p1080).outputSize(forSource: source)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
        XCTAssertEqual(size.width / size.height, source.width / source.height, accuracy: 0.01)
    }

    func testCapAppliesToTallSourcesToo() {
        let size = configuration(cap: .p1080).outputSize(forSource: CGSize(width: 1200, height: 3000))
        XCTAssertEqual(size.height, 1920)
        XCTAssertEqual(size.width, 768)
    }

    func testOutputDimensionsAreAlwaysEven() {
        let size = configuration(cap: .p1440).outputSize(forSource: CGSize(width: 3001, height: 1667))
        XCTAssertEqual(Int(size.width) % 2, 0)
        XCTAssertEqual(Int(size.height) % 2, 0)
    }

    func testWebcamOverlayStaysInsideTheFrameInEveryCorner() {
        let video = CGSize(width: 1920, height: 1080)
        for corner in OverlayCorner.allCases {
            let overlay = WebcamOverlayConfiguration(deviceID: nil,
                                                     shape: .roundedRectangle,
                                                     corner: corner,
                                                     sizeFraction: 0.25)
            let frame = overlay.frame(inVideoSize: video)
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(corner)")
            XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(corner)")
            XCTAssertLessThanOrEqual(frame.maxX, video.width, "\(corner)")
            XCTAssertLessThanOrEqual(frame.maxY, video.height, "\(corner)")
        }
    }

    func testCircleOverlayIsSquare() {
        let overlay = WebcamOverlayConfiguration(deviceID: nil, shape: .circle,
                                                 corner: .bottomTrailing, sizeFraction: 0.2)
        let frame = overlay.frame(inVideoSize: CGSize(width: 1280, height: 720))
        XCTAssertEqual(frame.width, frame.height)
    }
}

final class TimeFormattingTests: XCTestCase {

    func testClockSwitchesToHoursOnlyWhenNeeded() {
        XCTAssertEqual(TimeFormatting.clock(9), "00:09")
        XCTAssertEqual(TimeFormatting.clock(75), "01:15")
        XCTAssertEqual(TimeFormatting.clock(3671), "1:01:11")
    }

    func testTimecodeIncludesTenths() {
        XCTAssertEqual(TimeFormatting.timecode(83.44), "01:23.4")
        XCTAssertEqual(TimeFormatting.timecode(-5), "00:00.0")
    }
}

final class AudioMixerTests: XCTestCase {

    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 48_000,
                                       channels: 2,
                                       interleaved: false)!

    private func buffer(value: Float, frames: AVAudioFrameCount = 480) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) { data[frame] = value }
        }
        return buffer
    }

    private func sampleBuffer(value: Float, at seconds: Double) -> CMSampleBuffer {
        AudioConversion.sampleBuffer(from: buffer(value: value),
                                     presentationTime: CMTime(seconds: seconds, preferredTimescale: 48_000))!
    }

    private func firstSample(of sampleBuffer: CMSampleBuffer) -> Float {
        let pcm = AudioConversion.pcmBuffer(from: sampleBuffer, targetFormat: format)!
        return pcm.floatChannelData![0][0]
    }

    func testPrimaryPassesThroughWhenNothingIsQueued() throws {
        let mixer = AudioMixer(format: format)
        let mixed = try XCTUnwrap(mixer.mix(primary: sampleBuffer(value: 0.25, at: 1)))
        XCTAssertEqual(firstSample(of: mixed), 0.25, accuracy: 0.001)
    }

    func testOverlappingSecondaryAudioIsSummedIn() throws {
        let mixer = AudioMixer(format: format)
        mixer.enqueueSecondary(sampleBuffer(value: 0.3, at: 1))
        let mixed = try XCTUnwrap(mixer.mix(primary: sampleBuffer(value: 0.2, at: 1)))
        XCTAssertEqual(firstSample(of: mixed), 0.5, accuracy: 0.001)
    }

    func testMixedAudioIsClampedToTheValidRange() throws {
        let mixer = AudioMixer(format: format)
        mixer.enqueueSecondary(sampleBuffer(value: 0.9, at: 2))
        let mixed = try XCTUnwrap(mixer.mix(primary: sampleBuffer(value: 0.8, at: 2)))
        XCTAssertEqual(firstSample(of: mixed), 1.0, accuracy: 0.0001)
    }

    func testSecondaryAudioFromADifferentTimeIsNotMixedIn() throws {
        let mixer = AudioMixer(format: format)
        // 480 frames at 48 kHz is 10 ms, so a buffer at 5.0 s cannot overlap 1.0 s.
        mixer.enqueueSecondary(sampleBuffer(value: 0.5, at: 5))
        let mixed = try XCTUnwrap(mixer.mix(primary: sampleBuffer(value: 0.1, at: 1)))
        XCTAssertEqual(firstSample(of: mixed), 0.1, accuracy: 0.001)
    }

    func testStaleSecondaryAudioIsDiscardedRatherThanAccumulating() throws {
        let mixer = AudioMixer(format: format)
        mixer.enqueueSecondary(sampleBuffer(value: 0.4, at: 1))
        _ = mixer.mix(primary: sampleBuffer(value: 0, at: 2))
        // The 1.0 s buffer is now behind the primary clock and must be gone.
        let mixed = try XCTUnwrap(mixer.mix(primary: sampleBuffer(value: 0.1, at: 1)))
        XCTAssertEqual(firstSample(of: mixed), 0.1, accuracy: 0.001)
    }
}
