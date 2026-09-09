import AVFoundation
import AppKit
import ScreenCaptureKit
import XCTest
@testable import Snaplet

/// Runs a real ScreenCaptureKit stream into the real `RecordingWriter`.
///
/// This needs Screen & System Audio Recording permission for the test host, so
/// it skips itself when the permission is missing — CI and ordinary local runs
/// stay green. To run it, sign the test host with the same certificate the app
/// uses, so the granted permission applies:
///
///     CODE_SIGN_IDENTITY="Snaplet Dev" CODE_SIGN_STYLE=Manual \
///     xcodebuild -project Snaplet.xcodeproj -scheme Snaplet \
///       -destination 'platform=macOS,arch=arm64' \
///       test -only-testing:SnapletTests/LiveCaptureIntegrationTests
///
/// Synthetic frames cannot reproduce what ScreenCaptureKit actually delivers —
/// IOSurface backing, row padding, attachments, real timing — which is exactly
/// where recording was failing.
final class LiveCaptureIntegrationTests: XCTestCase {

    private var outputURL: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(),
                          "needs Screen & System Audio Recording for the test host")
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-live-\(UUID().uuidString).mp4")
    }

    override func tearDown() {
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        super.tearDown()
    }

    /// Captures each connected display for a couple of seconds and reports
    /// exactly how the writer fared, so a failure names the display it happened on.
    func testCapturesEveryDisplayIntoAPlayableFile() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        XCTAssertFalse(content.displays.isEmpty, "no displays are shareable")

        var failures: [String] = []

        for display in content.displays {
            let screen = await MainActor.run {
                NSScreen.screens.first { $0.displayID == display.displayID }
            }
            let scale = await MainActor.run { screen?.backingScaleFactor ?? 2 }
            let pixelSize = CGSize(width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
            let label = "display \(display.displayID) \(Int(pixelSize.width))x\(Int(pixelSize.height))@\(scale)x"

            do {
                let summary = try await record(display: display,
                                               content: content,
                                               pixelSize: pixelSize,
                                               seconds: 2)
                print("LIVE \(label): OK — \(summary)")
            } catch {
                let message = "LIVE \(label): FAILED — \(error)"
                print(message)
                failures.append(message)
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// The writer flushes a movie fragment every two seconds. Anything shorter
    /// never reaches the first flush, which is exactly where a recording that
    /// "works in testing" can start failing in real use.
    func testRecordsPastTheFirstFragmentBoundary() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)
        let screen = await MainActor.run {
            NSScreen.screens.first { $0.displayID == display.displayID }
        }
        let scale = await MainActor.run { screen?.backingScaleFactor ?? 2 }
        let pixelSize = CGSize(width: CGFloat(display.width) * scale,
                               height: CGFloat(display.height) * scale)

        let summary = try await record(display: display,
                                       content: content,
                                       pixelSize: pixelSize,
                                       seconds: 8)
        print("LIVE 8s: OK — \(summary)")
    }

    /// Composes a selection that crosses the boundary between two real
    /// displays. The unit tests cover the maths with synthetic snapshots; this
    /// checks it against whatever the machine is actually plugged into,
    /// including a mismatch in scale factors.
    func testASelectionSpanningTwoDisplaysComposesIntoOneImage() async throws {
        let snapshots = try await MainActor.run { ScreenshotService() }.captureAllDisplays()
        try XCTSkipUnless(snapshots.count >= 2, "needs two displays")

        // Order them left to right and straddle the seam between the first pair.
        let ordered = snapshots.sorted { $0.frame.minX < $1.frame.minX }
        let left = ordered[0], right = ordered[1]
        let seam = right.frame.minX
        let height = min(200, min(left.frame.height, right.frame.height) - 20)
        let selection = CGRect(x: seam - 150,
                               y: max(left.frame.minY, right.frame.minY) + 10,
                               width: 300,
                               height: height)

        XCTAssertTrue(MultiDisplayCompositor.spansMultipleDisplays(selection, snapshots: snapshots))
        let composed = try XCTUnwrap(MultiDisplayCompositor.composite(selection: selection,
                                                                     from: snapshots))

        let expectedScale = max(left.scale, right.scale)
        XCTAssertEqual(composed.scale, expectedScale, "should render at the sharper display's scale")
        XCTAssertEqual(CGFloat(composed.image.width), (selection.width * expectedScale).rounded(),
                       accuracy: 1)
        XCTAssertEqual(CGFloat(composed.image.height), (selection.height * expectedScale).rounded(),
                       accuracy: 1)

        // Both halves must carry real pixels, not a transparent gap.
        let sampler = PixelSampler(composed.image)
        let quarter = composed.image.width / 4
        let middle = composed.image.height / 2
        XCTAssertEqual(sampler.rgba(x: quarter, y: middle).a, 255, "left half is empty")
        XCTAssertEqual(sampler.rgba(x: quarter * 3, y: middle).a, 255, "right half is empty")

        print("LIVE span: \(composed.image.width)x\(composed.image.height) @\(composed.scale)x "
              + "across \(left.frame.size) @\(left.scale)x and \(right.frame.size) @\(right.scale)x")
    }

    /// The two capture-latency paths the documentation says are unmeasured.
    /// They need a real display and the screen-recording permission, which is
    /// exactly why they could not be measured in CI.
    func testMeasuresCaptureLatency() async throws {
        let service = await MainActor.run { ScreenshotService() }
        let path = ProcessInfo.processInfo.environment["SNAPLET_PERF_OUT"] ?? "/tmp/snaplet-perf.txt"

        func report(_ name: String, _ samples: [Double]) {
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            let p90 = sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.9).rounded()))]
            let line = String(format: "%@: n=%d median %.0f ms  min %.0f ms  p90 %.0f ms\n",
                              name, samples.count, median * 1000,
                              sorted.first! * 1000, p90 * 1000)
            print("PERF " + line)
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }

        // shortcut -> overlay: everything that happens before the user can drag.
        var toOverlay: [Double] = []
        var snapshots: [DisplaySnapshot] = []
        for _ in 0..<7 {
            let start = ContinuousClock.now
            snapshots = try await service.captureAllDisplays()
            toOverlay.append(start.secondsElapsed)
        }
        report("shortcut→overlay (\(snapshots.count) displays)", toOverlay)

        // selection -> clipboard: compose the region, encode it, put it on the
        // pasteboard. A 600x400 point selection is a typical bug-report crop.
        let display = try XCTUnwrap(snapshots.first)
        let selection = CGRect(x: display.frame.minX + 40, y: display.frame.minY + 40,
                               width: 600, height: 400)
        var toClipboard: [Double] = []
        for _ in 0..<7 {
            let start = ContinuousClock.now
            let composed = MultiDisplayCompositor.composite(selection: selection, from: snapshots)
            let image = try XCTUnwrap(composed?.image)
            await MainActor.run { Clipboard.copy(image: image) }
            toClipboard.append(start.secondsElapsed)
        }
        report("selection→clipboard (600×400 pt)", toClipboard)

        print("PERF written to \(path)")
    }

    // MARK: - The production path

    /// Drives the real `RecordingSession` rather than a copy of it, so the
    /// stream configuration, the filter and the writer are exactly what the app
    /// uses. Covers all three targets, because area and window recording build
    /// their filters differently from full screen.
    func testRecordingSessionCapturesEveryTargetKind() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)
        let frame = try await MainActor.run { () -> CGRect in
            let screen = try XCTUnwrap(NSScreen.screens.first { $0.displayID == display.displayID })
            return screen.frame
        }

        var targets: [(String, RecordingConfiguration.Target)] = [
            ("full screen", .display(display.displayID)),
            ("area", .area(displayID: display.displayID,
                           rect: CGRect(x: frame.minX + 100, y: frame.minY + 100,
                                        width: 640, height: 480)))
        ]
        if let window = content.windows.first(where: {
            $0.isOnScreen && $0.windowLayer == 0
                && $0.frame.width >= 200 && $0.frame.height >= 200
                && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }) {
            targets.append(("window", .window(window.windowID)))
        }

        var failures: [String] = []
        for (label, target) in targets {
            do {
                let summary = try await runSession(target: target, seconds: 3)
                print("LIVE session/\(label): OK — \(summary)")
            } catch {
                let message = "LIVE session/\(label): FAILED — \(error)"
                print(message)
                failures.append(message)
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// The same recording, several times over. A failure that moves between
    /// targets from run to run is a race or a resource that is not released,
    /// not a problem with any one capture target.
    func testRepeatedRecordingsAllSucceed() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)

        var failures: [String] = []
        for attempt in 1...5 {
            do {
                let summary = try await runSession(target: .display(display.displayID), seconds: 4)
                print("LIVE repeat \(attempt): OK — \(summary)")
            } catch {
                print("LIVE repeat \(attempt): FAILED — \(error)")
                failures.append("attempt \(attempt)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "failed on \(failures.joined(separator: ", ")) of 5")
    }

    private func runSession(target: RecordingConfiguration.Target,
                            seconds: Double) async throws -> String {
        var configuration = RecordingConfiguration(target: target)
        configuration.frameRate = 60
        configuration.capturesSystemAudio = false
        configuration.capturesMicrophone = false
        configuration.countdownSeconds = 0

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-session-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let session = RecordingSession(configuration: configuration, outputURL: url)
        var unexpected: SnapletError?
        session.onUnexpectedStop = { unexpected = $0 }

        try await MainActor.run { Task { try await session.start() } }.value
        try await Task.sleep(for: .seconds(seconds))

        if let unexpected { throw unexpected }
        let output = try await session.stop()

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "no video track")
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        return "\(Int(size.width))x\(Int(size.height)) · \(String(format: "%.2f", duration))s"
    }

    // MARK: - Harness

    private func record(display: SCDisplay,
                        content: SCShareableContent,
                        pixelSize: CGSize,
                        seconds: Double) async throws -> String {
        let ownApplication = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplication.map { [$0] } ?? [],
                                     exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.preservesAspectRatio = true
        configuration.scalesToFit = false
        configuration.capturesAudio = false

        let writer = try RecordingWriter(outputURL: outputURL,
                                         videoSize: pixelSize,
                                         frameRate: 60,
                                         hasAudio: false,
                                         needsPixelBufferInput: false)

        let handler = StreamOutputHandler()
        let queue = DispatchQueue(label: "snaplet.test.frames")
        handler.onScreen = { sampleBuffer in
            guard Self.isComplete(sampleBuffer) else { return }
            writer.appendVideo(sampleBuffer)
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: handler)
        try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try? await stream.stopCapture()

        if let failure = writer.failure {
            throw NSError(domain: "LiveCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(failure.localizedDescription) [\(writer.diagnosticSummary)]"
            ])
        }

        let url = try await writer.finish()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "no video track was written")
        XCTAssertGreaterThan(duration, 0.2, "file is too short to be a real recording")
        return "\(writer.diagnosticSummary) · \(String(format: "%.2f", duration))s"
    }

    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                        createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
