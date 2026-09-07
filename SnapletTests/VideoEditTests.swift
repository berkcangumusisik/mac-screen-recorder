import AVFoundation
import CoreImage
import XCTest
@testable import Snaplet

final class ZoomEmphasisTests: XCTestCase {

    private let zoom = ZoomEmphasis(start: 2,
                                    end: 6,
                                    focus: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25),
                                    ramp: 0.5)

    func testIntensityIsZeroOutsideTheRange() {
        XCTAssertEqual(zoom.intensity(at: 1.9), 0)
        XCTAssertEqual(zoom.intensity(at: 6.1), 0)
    }

    func testIntensityRampsInAndOut() {
        XCTAssertEqual(zoom.intensity(at: 2.0), 0, accuracy: 0.001)
        XCTAssertEqual(zoom.intensity(at: 2.5), 1, accuracy: 0.001)
        XCTAssertEqual(zoom.intensity(at: 4.0), 1, accuracy: 0.001)
        XCTAssertEqual(zoom.intensity(at: 6.0), 0, accuracy: 0.001)
        XCTAssertGreaterThan(zoom.intensity(at: 2.25), 0)
        XCTAssertLessThan(zoom.intensity(at: 2.25), 1)
    }

    func testRampIsClampedForVeryShortRanges() {
        let brief = ZoomEmphasis(start: 0, end: 0.4,
                                 focus: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                                 ramp: 5)
        XCTAssertEqual(brief.intensity(at: 0.2), 1, accuracy: 0.001)
        XCTAssertEqual(brief.intensity(at: 0), 0, accuracy: 0.001)
    }

    func testMaximumScaleComesFromTheLargerFocusEdge() {
        XCTAssertEqual(zoom.maximumScale, 4, accuracy: 0.001)
        let wide = ZoomEmphasis(start: 0, end: 1,
                                focus: CGRect(x: 0, y: 0, width: 0.5, height: 0.2))
        XCTAssertEqual(wide.maximumScale, 2, accuracy: 0.001)
    }

    func testTransformIsIdentityOutsideTheRange() {
        XCTAssertEqual(zoom.transform(at: 10, videoSize: CGSize(width: 100, height: 100)), .identity)
    }

    func testFullyZoomedTransformPutsTheFocusCentreAtTheFrameCentre() {
        let size = CGSize(width: 400, height: 400)
        let transform = zoom.transform(at: 4, videoSize: size)
        // Focus centre is (0.375, 0.375) -> (150, 150) in pixels.
        let mapped = CGPoint(x: 150, y: 150).applying(transform)
        XCTAssertEqual(mapped.x, 200, accuracy: 0.5)
        XCTAssertEqual(mapped.y, 200, accuracy: 0.5)
    }

    func testFlippedTransformMirrorsTheVerticalAxis() {
        let size = CGSize(width: 400, height: 400)
        let flipped = zoom.transform(at: 4, videoSize: size, flipY: true)
        // In Core Image space the focus centre is at y = 400 - 150 = 250.
        let mapped = CGPoint(x: 150, y: 250).applying(flipped)
        XCTAssertEqual(mapped.x, 200, accuracy: 0.5)
        XCTAssertEqual(mapped.y, 200, accuracy: 0.5)
    }
}

final class VideoEditModelTests: XCTestCase {

    func testOverlayVisibilityIsInclusiveOfItsBounds() {
        let overlay = VideoOverlay(kind: .redaction, start: 1, end: 2,
                                   frame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertFalse(overlay.isVisible(at: 0.99))
        XCTAssertTrue(overlay.isVisible(at: 1))
        XCTAssertTrue(overlay.isVisible(at: 1.5))
        XCTAssertTrue(overlay.isVisible(at: 2))
        XCTAssertFalse(overlay.isVisible(at: 2.01))
    }

    func testOutputSizeNeverUpscalesAndStaysEven() {
        var edit = VideoEdit()
        edit.resolutionCap = .p2160
        XCTAssertEqual(edit.outputSize(forSource: CGSize(width: 640, height: 360)),
                       CGSize(width: 640, height: 360))
        edit.resolutionCap = .p1080
        let capped = edit.outputSize(forSource: CGSize(width: 3841, height: 2161))
        XCTAssertEqual(capped.width, 1920)
        XCTAssertEqual(Int(capped.height) % 2, 0)
    }

    func testCanvasSizeGrowsWhenStylingIsApplied() {
        var edit = VideoEdit()
        let source = CGSize(width: 1280, height: 720)
        XCTAssertEqual(edit.canvasSize(forSource: source), CGSize(width: 1280, height: 720))
        edit.style = .studio
        let canvas = edit.canvasSize(forSource: source)
        XCTAssertGreaterThan(canvas.width, 1280)
        XCTAssertGreaterThan(canvas.height, 720)
    }

    func testContentRectIsTheWholeCanvasWithoutStyling() {
        let edit = VideoEdit()
        XCTAssertEqual(edit.contentRectInCanvas(sourceSize: CGSize(width: 100, height: 100)),
                       CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testContentRectIsInsetAndCentredWithStyling() {
        var edit = VideoEdit()
        edit.style = .clean
        let rect = edit.contentRectInCanvas(sourceSize: CGSize(width: 1000, height: 800))
        XCTAssertGreaterThan(rect.minX, 0)
        XCTAssertLessThan(rect.maxX, 1)
        XCTAssertEqual(rect.minX, 1 - rect.maxX, accuracy: 0.002)
    }

    func testGIFRangeIsCappedAtTheDocumentedLimit() {
        let clamped = GIFExportOptions.clampedRange(start: 5, end: 200)
        XCTAssertEqual(clamped.start, 5)
        XCTAssertEqual(clamped.end, 5 + GIFExportOptions.maximumDuration)

        let short = GIFExportOptions.clampedRange(start: 0, end: 3)
        XCTAssertEqual(short.end, 3)
    }
}

/// Renders frames through the same object the exporter uses and checks that a
/// redaction really covers its region — including while a zoom is active.
final class VideoRedactionCoverageTests: XCTestCase {

    private let context = CIContext(options: nil)
    private let sourceSize = CGSize(width: 320, height: 240)

    private func sourceFrame() -> CIImage {
        CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(origin: .zero, size: sourceSize))
    }

    private func sample(_ image: CIImage, atNormalised point: CGPoint, canvas: CGSize) -> (Int, Int, Int) {
        let rendered = context.createCGImage(image, from: CGRect(origin: .zero, size: canvas))!
        let sampler = PixelSampler(rendered)
        let x = min(rendered.width - 1, max(0, Int(point.x * CGFloat(rendered.width))))
        let y = min(rendered.height - 1, max(0, Int(point.y * CGFloat(rendered.height))))
        let pixel = sampler.rgba(x: x, y: y)
        return (pixel.r, pixel.g, pixel.b)
    }

    func testRedactionCoversEveryFrameInItsRange() {
        var edit = VideoEdit()
        edit.trimEnd = 3
        edit.overlays = [VideoOverlay(kind: .redaction,
                                      start: 1,
                                      end: 2,
                                      frame: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))]
        let renderer = VideoFrameRenderer(edit: edit, sourceSize: sourceSize)

        for time in stride(from: 1.0, through: 2.0, by: 0.05) {
            let output = renderer.render(sourceFrame(), at: time)
            let pixel = sample(output, atNormalised: CGPoint(x: 0.5, y: 0.5), canvas: renderer.canvasSize)
            XCTAssertLessThan(pixel.0, 60, "frame at \(time)s is not covered")
        }
        // Just outside the range the original content is visible again.
        let before = sample(renderer.render(sourceFrame(), at: 0.9),
                            atNormalised: CGPoint(x: 0.5, y: 0.5), canvas: renderer.canvasSize)
        XCTAssertGreaterThan(before.0, 200)
    }

    func testRedactionStaysOverTheContentWhileZoomed() {
        var edit = VideoEdit()
        edit.trimEnd = 4
        edit.overlays = [VideoOverlay(kind: .redaction,
                                      start: 0,
                                      end: 4,
                                      frame: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))]
        edit.zooms = [ZoomEmphasis(start: 1, end: 3,
                                   focus: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3),
                                   ramp: 0.4)]
        let renderer = VideoFrameRenderer(edit: edit, sourceSize: sourceSize)

        for time in stride(from: 1.0, through: 3.0, by: 0.1) {
            let output = renderer.render(sourceFrame(), at: time)
            let pixel = sample(output, atNormalised: CGPoint(x: 0.5, y: 0.5), canvas: renderer.canvasSize)
            XCTAssertLessThan(pixel.0, 60, "zoomed frame at \(time)s exposes the redacted region")
        }
    }

    func testRedactionSurvivesPresentationStyling() {
        var edit = VideoEdit()
        edit.trimEnd = 2
        edit.style = .midnight
        edit.overlays = [VideoOverlay(kind: .redaction,
                                      start: 0,
                                      end: 2,
                                      frame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))]
        let renderer = VideoFrameRenderer(edit: edit, sourceSize: sourceSize)
        let content = edit.contentRectInCanvas(sourceSize: sourceSize)
        let centre = CGPoint(x: content.midX, y: content.midY)

        for time in stride(from: 0.0, through: 2.0, by: 0.1) {
            let output = renderer.render(sourceFrame(), at: time)
            let pixel = sample(output, atNormalised: centre, canvas: renderer.canvasSize)
            XCTAssertLessThan(pixel.0, 60, "styled frame at \(time)s exposes the redacted region")
        }
    }
}

/// End-to-end pass over a real file: build the composition the exporter uses and
/// render frames out of it.
final class VideoCompositionIntegrationTests: XCTestCase {

    private var url: URL!

    override func setUp() async throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-test-\(UUID().uuidString).mp4")
        try await TestVideo.make(url: url, seconds: 2, frameRate: 10, color: .red)
    }

    override func tearDown() async throws {
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func testCompositionAppliesRedactionToRenderedFrames() async throws {
        let asset = AVURLAsset(url: url)
        let size = try await VideoCompositionBuilder.displaySize(of: asset)
        XCTAssertEqual(size, CGSize(width: 320, height: 240))

        var edit = VideoEdit()
        edit.trimStart = 0
        edit.trimEnd = 2
        edit.overlays = [VideoOverlay(kind: .redaction,
                                      start: 0.5,
                                      end: 1.5,
                                      frame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))]

        let built = try await VideoCompositionBuilder.make(asset: asset,
                                                           edit: edit,
                                                           sourceSize: size,
                                                           frameRate: 10)
        XCTAssertEqual(built.renderSize, CGSize(width: 320, height: 240))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = built.composition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for seconds in [0.6, 0.9, 1.2, 1.4] {
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let sampler = PixelSampler(image)
            let pixel = sampler.rgba(x: image.width / 2, y: image.height / 2)
            XCTAssertLessThan(pixel.r, 70, "frame at \(seconds)s was not redacted")
        }

        let (uncovered, _) = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600))
        let pixel = PixelSampler(uncovered).rgba(x: uncovered.width / 2, y: uncovered.height / 2)
        XCTAssertGreaterThan(pixel.r, 150, "frames outside the range should be untouched")
    }

    func testTrimmedExportProducesAShorterPlayableFile() async throws {
        let asset = AVURLAsset(url: url)
        let size = try await VideoCompositionBuilder.displaySize(of: asset)
        var edit = VideoEdit()
        edit.trimStart = 0.5
        edit.trimEnd = 1.5

        let exporter = await VideoExporter()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplet-export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await exporter.exportMovie(asset: asset,
                                                    edit: edit,
                                                    sourceSize: size,
                                                    frameRate: 10,
                                                    to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        let exported = AVURLAsset(url: result)
        let duration = try await exported.load(.duration).seconds
        XCTAssertEqual(duration, 1.0, accuracy: 0.35)
    }
}
