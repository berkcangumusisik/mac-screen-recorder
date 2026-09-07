import XCTest
@testable import Snaplet

/// The exported file must not contain the content a redaction covers. These
/// tests read the rendered pixels back and check the covered region.
final class RedactionOutputTests: XCTestCase {

    private func request(with annotations: [Annotation], source: CGImage) -> RenderRequest {
        RenderRequest(source: source,
                      cropRect: CGRect(x: 0, y: 0, width: source.width, height: source.height),
                      quarterTurns: 0,
                      annotations: annotations,
                      style: nil,
                      scale: 1)
    }

    private func makeRequest(annotations: [Annotation],
                             crop: CGRect? = nil,
                             turns: Int = 0) -> RenderRequest {
        let image = TestImages.solid(width: 200, height: 200, color: .white)
        return RenderRequest(source: image,
                             cropRect: crop ?? CGRect(x: 0, y: 0, width: 200, height: 200),
                             quarterTurns: turns,
                             annotations: annotations,
                             style: nil,
                             scale: 2)
    }

    func testRedactionCoversItsRegionWithOpaquePixels() throws {
        var redaction = Annotation(kind: .redaction, frame: CGRect(x: 50, y: 50, width: 80, height: 40))
        redaction.strokeColor = RGBAColor(red: 0, green: 0, blue: 0)
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(makeRequest(annotations: [redaction])))
        let sampler = PixelSampler(rendered)

        for x in stride(from: 52, to: 128, by: 8) {
            for y in stride(from: 52, to: 88, by: 8) {
                XCTAssertTrue(sampler.isApproximately((0, 0, 0), atX: x, y: y, tolerance: 4),
                              "pixel (\(x), \(y)) inside the redaction is not opaque")
                XCTAssertEqual(sampler.rgba(x: x, y: y).a, 255)
            }
        }
        XCTAssertTrue(sampler.isApproximately((255, 255, 255), atX: 10, y: 10),
                      "content outside the redaction must be untouched")
    }

    func testRedactionSurvivesCropAndRotation() throws {
        var redaction = Annotation(kind: .redaction, frame: CGRect(x: 60, y: 60, width: 60, height: 60))
        redaction.strokeColor = RGBAColor(red: 0, green: 0, blue: 0)
        let request = makeRequest(annotations: [redaction],
                                  crop: CGRect(x: 40, y: 40, width: 120, height: 120),
                                  turns: 1)
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(request))
        let sampler = PixelSampler(rendered)
        // The redaction sits at source (60,60)-(120,120); after cropping at
        // (40,40) it is (20,20)-(80,80), and a clockwise quarter turn of a
        // 120×120 square maps that to (40,20)-(100,80).
        XCTAssertTrue(sampler.isApproximately((0, 0, 0), atX: 60, y: 50, tolerance: 4))
        XCTAssertTrue(sampler.isApproximately((255, 255, 255), atX: 10, y: 10))
    }

    func testPixelateReplacesFineDetailInsideItsRegion() throws {
        // Two-pixel stripes averaged into 16-pixel blocks must come out grey.
        let source = TestImages.stripes(width: 120, height: 120, barWidth: 2)
        var effect = Annotation(kind: .pixelate, frame: CGRect(x: 40, y: 40, width: 48, height: 48))
        effect.effectStrength = 16
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(request(with: [effect], source: source)))
        let output = PixelSampler(rendered)

        var sawIntermediateTone = false
        for x in stride(from: 44, to: 84, by: 3) {
            let pixel = output.rgba(x: x, y: 60)
            if pixel.r > 40 && pixel.r < 215 { sawIntermediateTone = true }
        }
        XCTAssertTrue(sawIntermediateTone, "pixelate left the striped detail intact")

        // Outside the region the stripes are still crisp black and white.
        let original = PixelSampler(source)
        for x in stride(from: 4, to: 36, by: 2) {
            XCTAssertEqual(output.rgba(x: x, y: 60).r, original.rgba(x: x, y: 60).r, accuracy: 12)
        }
    }

    func testBlurSoftensFineDetailInsideItsRegion() throws {
        let source = TestImages.stripes(width: 120, height: 120, barWidth: 2)
        var effect = Annotation(kind: .blur, frame: CGRect(x: 40, y: 40, width: 48, height: 48))
        effect.effectStrength = 10
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(request(with: [effect], source: source)))
        let output = PixelSampler(rendered)

        var sawIntermediateTone = false
        for x in stride(from: 46, to: 82, by: 3) {
            let pixel = output.rgba(x: x, y: 60)
            if pixel.r > 40 && pixel.r < 215 { sawIntermediateTone = true }
        }
        XCTAssertTrue(sawIntermediateTone, "blur left the striped detail intact")
    }

    func testExportedDataDecodesToTheRenderedPixels() throws {
        var redaction = Annotation(kind: .redaction, frame: CGRect(x: 20, y: 20, width: 60, height: 60))
        redaction.strokeColor = RGBAColor(red: 0, green: 0, blue: 0)
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(makeRequest(annotations: [redaction])))
        let data = try ImageExporter.data(from: rendered, format: .png)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, rendered.width)
        XCTAssertEqual(decoded.height, rendered.height)
        let sampler = PixelSampler(decoded)
        XCTAssertTrue(sampler.isApproximately((0, 0, 0), atX: 50, y: 50, tolerance: 4))
        // A single-image PNG carries exactly one frame: there is no second
        // layer holding the original content.
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
    }
}
