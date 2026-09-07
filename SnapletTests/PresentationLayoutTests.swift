import XCTest
@testable import Snaplet

final class PresentationLayoutTests: XCTestCase {

    private func style(_ mutate: (inout StylePreset) -> Void) -> StylePreset {
        var preset = StylePreset.clean
        mutate(&preset)
        return preset
    }

    func testPaddingScalesWithTheLongestEdge() {
        let preset = style { $0.paddingFraction = 0.1; $0.showsWindowFrame = false; $0.aspect = .original }
        let layout = PresentationRenderer.layout(contentSize: CGSize(width: 1000, height: 500), style: preset)
        XCTAssertEqual(layout.canvasSize.width, 1200)
        XCTAssertEqual(layout.canvasSize.height, 700)
    }

    func testContentIsCentredHorizontally() {
        let preset = style { $0.paddingFraction = 0.08; $0.showsWindowFrame = false; $0.aspect = .original }
        let layout = PresentationRenderer.layout(contentSize: CGSize(width: 800, height: 600), style: preset)
        let leftGap = layout.contentRect.minX
        let rightGap = layout.canvasSize.width - layout.contentRect.maxX
        XCTAssertEqual(leftGap, rightGap, accuracy: 0.5)
    }

    func testSquareAspectProducesASquareCanvas() {
        let preset = style { $0.aspect = .square; $0.showsWindowFrame = false }
        let layout = PresentationRenderer.layout(contentSize: CGSize(width: 1600, height: 400), style: preset)
        XCTAssertEqual(layout.canvasSize.width, layout.canvasSize.height, accuracy: 1)
    }

    func testVerticalAspectNeverCropsTheContent() {
        let preset = style { $0.aspect = .vertical; $0.showsWindowFrame = false }
        let content = CGSize(width: 1920, height: 1080)
        let layout = PresentationRenderer.layout(contentSize: content, style: preset)
        XCTAssertGreaterThanOrEqual(layout.canvasSize.width, content.width)
        XCTAssertGreaterThanOrEqual(layout.canvasSize.height, content.height)
        XCTAssertGreaterThanOrEqual(layout.contentRect.minX, 0)
        XCTAssertLessThanOrEqual(layout.contentRect.maxY, layout.canvasSize.height)
    }

    func testWindowFrameAddsATitleBarAboveTheContent() {
        let preset = style { $0.showsWindowFrame = true; $0.aspect = .original }
        let layout = PresentationRenderer.layout(contentSize: CGSize(width: 1000, height: 600), style: preset)
        XCTAssertGreaterThan(layout.titleBarHeight, 0)
        XCTAssertEqual(layout.contentRect.minY, layout.frameRect.minY + layout.titleBarHeight, accuracy: 0.5)
    }

    func testCaptionReservesSpaceAboveTheFrame() {
        let withoutCaption = PresentationRenderer.layout(contentSize: CGSize(width: 800, height: 600),
                                                         style: style { $0.aspect = .original })
        let withCaption = PresentationRenderer.layout(contentSize: CGSize(width: 800, height: 600),
                                                      style: style {
                                                          $0.aspect = .original
                                                          $0.title = "Release notes"
                                                      })
        XCTAssertGreaterThan(withCaption.canvasSize.height, withoutCaption.canvasSize.height)
        XCTAssertNotNil(withCaption.titleRect)
    }

    func testRenderProducesTheLaidOutCanvasSize() throws {
        let preset = style { $0.aspect = .wide; $0.showsWindowFrame = true }
        let content = TestImages.solid(width: 400, height: 300)
        let layout = PresentationRenderer.layout(contentSize: CGSize(width: 400, height: 300), style: preset)
        let rendered = try XCTUnwrap(PresentationRenderer.render(content: content, style: preset))
        XCTAssertEqual(rendered.width, Int(layout.canvasSize.width))
        XCTAssertEqual(rendered.height, Int(layout.canvasSize.height))
    }

    func testLongestEdgeCapDownscalesWithoutUpscaling() throws {
        let preset = style { $0.aspect = .original; $0.paddingFraction = 0 }
        let content = TestImages.solid(width: 2000, height: 1000)
        let capped = try XCTUnwrap(PresentationRenderer.render(content: content, style: preset, maxLongestEdge: 1000))
        XCTAssertLessThanOrEqual(max(capped.width, capped.height), 1002)

        let small = TestImages.solid(width: 100, height: 50)
        let notUpscaled = try XCTUnwrap(PresentationRenderer.render(content: small, style: preset, maxLongestEdge: 4000))
        XCTAssertLessThan(max(notUpscaled.width, notUpscaled.height), 4000)
    }
}
