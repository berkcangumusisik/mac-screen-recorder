import AVFoundation
import AppKit
import XCTest
@testable import Snaplet

/// Timings used to keep the documentation honest.
///
/// These assert correctness, not speed — a slow machine must not fail the
/// build. Each measurement is appended to `/tmp/snaplet-perf.txt` so the
/// numbers in `docs/performance.md` can be reproduced:
///
///     rm -f /tmp/snaplet-perf.txt
///     xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -destination 'platform=macOS' \
///       test -only-testing:SnapletTests/PerformanceMeasurementTests
///     cat /tmp/snaplet-perf.txt
final class PerformanceMeasurementTests: XCTestCase {

    private static let outputPath = ProcessInfo.processInfo.environment["SNAPLET_PERF_OUT"]
        ?? "/tmp/snaplet-perf.txt"

    /// Results are appended to a file because test `print` output does not
    /// reach xcodebuild's stdout.
    private func report(_ name: String, _ samples: [Double]) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let line = String(format: "%@: n=%d median %.1f ms  min %.1f ms  max %.1f ms\n",
                          name, samples.count, median * 1000,
                          sorted.first! * 1000, sorted.last! * 1000)
        print("PERF " + line)

        let url = URL(fileURLWithPath: Self.outputPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func time(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func annotations(count: Int, in size: CGSize) -> [Annotation] {
        (0..<count).map { index in
            let kinds: [Annotation.Kind] = [.arrow, .rectangle, .ellipse, .step, .redaction, .blur]
            var annotation = Annotation(kind: kinds[index % kinds.count],
                                        frame: CGRect(x: CGFloat(index) * 90 + 40,
                                                      y: CGFloat(index) * 60 + 40,
                                                      width: 260,
                                                      height: 160))
            annotation.number = index + 1
            return annotation
        }
    }

    func testAnnotatedExportOfA4KScreenshot() throws {
        let size = CGSize(width: 3840, height: 2160)
        let source = TestImages.split(width: Int(size.width), height: Int(size.height))
        let request = RenderRequest(source: source,
                                    cropRect: CGRect(origin: .zero, size: size),
                                    quarterTurns: 0,
                                    annotations: annotations(count: 8, in: size),
                                    style: nil,
                                    scale: 2)
        var samples: [Double] = []
        var bytes = 0
        for _ in 0..<5 {
            samples.append(time {
                guard let image = AnnotationRenderer.renderFlat(request) else { return }
                bytes = (try? ImageExporter.data(from: image, format: .png).count) ?? 0
            })
        }
        XCTAssertGreaterThan(bytes, 0)
        report("4K annotated render + PNG encode", samples)
    }

    func testStyledPresentationRenderOfA4KScreenshot() throws {
        let content = TestImages.split(width: 3840, height: 2160)
        var samples: [Double] = []
        var rendered: CGImage?
        for _ in 0..<5 {
            samples.append(time {
                rendered = PresentationRenderer.render(content: content, style: .studio)
            })
        }
        XCTAssertNotNil(rendered)
        report("4K styled presentation render", samples)
    }

    func testTextRecognitionOnAFullHDScreenshot() async throws {
        let image = TestImages.make(width: 1920, height: 1080) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
            context.translateBy(x: 0, y: 1080)
            context.scaleBy(x: 1, y: -1)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            for line in 0..<20 {
                ("Line \(line): the deployment finished with 0 errors and 3 warnings" as NSString)
                    .draw(in: CGRect(x: 40, y: 40 + line * 48, width: 1840, height: 44),
                          withAttributes: [.font: NSFont.systemFont(ofSize: 30),
                                           .foregroundColor: NSColor.black])
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        let service = TextRecognitionService()
        var samples: [Double] = []
        var lineCount = 0
        for _ in 0..<3 {
            let start = ContinuousClock.now
            lineCount = try await service.recognize(in: image, languages: ["en-US"]).lines.count
            samples.append(start.secondsElapsed)
        }
        XCTAssertGreaterThan(lineCount, 10)
        report("1080p text recognition (20 lines)", samples)
    }

    func testVideoExportOfAShortClip() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-perf-\(UUID().uuidString).mp4")
        try await TestVideo.make(url: source, size: CGSize(width: 1280, height: 720),
                                 seconds: 5, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: source) }

        let asset = AVURLAsset(url: source)
        let size = try await VideoCompositionBuilder.displaySize(of: asset)
        var edit = VideoEdit()
        edit.trimStart = 0
        edit.trimEnd = 5
        edit.overlays = [VideoOverlay(kind: .redaction, start: 0, end: 5,
                                      frame: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.2))]
        edit.zooms = [ZoomEmphasis(start: 1, end: 3,
                                   focus: CGRect(x: 0.25, y: 0.25, width: 0.4, height: 0.4))]

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-perf-out-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        let exporter = await VideoExporter()
        let start = ContinuousClock.now
        let result = try await exporter.exportMovie(asset: asset, edit: edit, sourceSize: size,
                                                    frameRate: 30, to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        report("5 s 720p export with redaction + zoom", [start.secondsElapsed])
    }
}
