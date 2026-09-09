import AppKit
import XCTest
@testable import Snaplet

/// A selection that crosses two monitors has to come back as one image, at the
/// right size, with each display's pixels in the right place — including when
/// the monitors have different scale factors.
final class MultiDisplayCompositorTests: XCTestCase {

    /// Left: 1000×800 points at 2×. Right: sits at x = 1000, 1200×800 at 1×.
    /// The layout Snaplet is actually being used on.
    private func snapshots(leftColor: NSColor = .red,
                           rightColor: NSColor = .blue) -> [DisplaySnapshot] {
        let left = DisplaySnapshot(displayID: 1,
                                   frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                   scale: 2,
                                   image: TestImages.solid(width: 2000, height: 1600, color: leftColor))
        let right = DisplaySnapshot(displayID: 2,
                                    frame: CGRect(x: 1000, y: 0, width: 1200, height: 800),
                                    scale: 1,
                                    image: TestImages.solid(width: 1200, height: 800, color: rightColor))
        return [left, right]
    }

    func testASelectionInsideOneDisplayIsJustACrop() throws {
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: 100, y: 100, width: 200, height: 100),
            from: snapshots()))
        XCTAssertEqual(result.scale, 2)
        XCTAssertEqual(result.image.width, 400)
        XCTAssertEqual(result.image.height, 200)
    }

    func testASpanningSelectionIsRenderedAtTheHighestScaleInvolved() throws {
        // 400 points wide, straddling the boundary at x = 1000.
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: 800, y: 300, width: 400, height: 200),
            from: snapshots()))
        XCTAssertEqual(result.scale, 2, "downscaling to the 1× display would lose detail")
        XCTAssertEqual(result.image.width, 800)
        XCTAssertEqual(result.image.height, 400)
    }

    func testEachDisplayContributesItsOwnHalf() throws {
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: 800, y: 300, width: 400, height: 200),
            from: snapshots(leftColor: .red, rightColor: .blue)))
        let sampler = PixelSampler(result.image)

        // Left 200 points (400 px) come from the red display, the rest from blue.
        XCTAssertTrue(sampler.isApproximately((255, 0, 0), atX: 100, y: 200), "left half should be red")
        XCTAssertTrue(sampler.isApproximately((0, 0, 255), atX: 700, y: 200), "right half should be blue")
    }

    func testTheSeamLandsWhereTheDisplaysMeet() throws {
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: 800, y: 300, width: 400, height: 200),
            from: snapshots(leftColor: .red, rightColor: .blue)))
        let sampler = PixelSampler(result.image)
        // The boundary is 200 points into the selection, so 400 px in.
        XCTAssertTrue(sampler.isApproximately((255, 0, 0), atX: 395, y: 200))
        XCTAssertTrue(sampler.isApproximately((0, 0, 255), atX: 405, y: 200))
    }

    func testAreaNoDisplayCoversStaysTransparent() throws {
        // Two displays with a vertical offset leave an uncovered corner.
        let tall = DisplaySnapshot(displayID: 1,
                                   frame: CGRect(x: 0, y: 0, width: 500, height: 800),
                                   scale: 1,
                                   image: TestImages.solid(width: 500, height: 800, color: .red))
        let short = DisplaySnapshot(displayID: 2,
                                    frame: CGRect(x: 500, y: 0, width: 500, height: 400),
                                    scale: 1,
                                    image: TestImages.solid(width: 500, height: 400, color: .blue))
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: 400, y: 300, width: 200, height: 300),
            from: [tall, short]))
        let sampler = PixelSampler(result.image)

        // Top-right of the selection is above the short display: nothing there.
        XCTAssertEqual(sampler.rgba(x: 150, y: 20).a, 0, "uncovered area must not be invented")
        // Bottom-right is on the short display.
        XCTAssertEqual(sampler.rgba(x: 150, y: 280).a, 255)
    }

    func testSelectionsOutsideEveryDisplayProduceNothing() {
        XCTAssertNil(MultiDisplayCompositor.composite(
            selection: CGRect(x: 5000, y: 5000, width: 100, height: 100),
            from: snapshots()))
    }

    func testDetectsWhetherASelectionSpansDisplays() {
        let all = snapshots()
        XCTAssertFalse(MultiDisplayCompositor.spansMultipleDisplays(
            CGRect(x: 10, y: 10, width: 100, height: 100), snapshots: all))
        XCTAssertTrue(MultiDisplayCompositor.spansMultipleDisplays(
            CGRect(x: 900, y: 10, width: 300, height: 100), snapshots: all))
    }

    func testNegativeOriginDisplaysComposeCorrectly() throws {
        // A monitor placed to the left of the primary one has a negative origin.
        let leftOfPrimary = DisplaySnapshot(displayID: 3,
                                            frame: CGRect(x: -1600, y: 0, width: 1600, height: 900),
                                            scale: 1,
                                            image: TestImages.solid(width: 1600, height: 900,
                                                                    color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let primary = DisplaySnapshot(displayID: 1,
                                      frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                      scale: 2,
                                      image: TestImages.solid(width: 2000, height: 1600, color: .red))
        let result = try XCTUnwrap(MultiDisplayCompositor.composite(
            selection: CGRect(x: -200, y: 100, width: 400, height: 200),
            from: [leftOfPrimary, primary]))
        XCTAssertEqual(result.scale, 2)
        let sampler = PixelSampler(result.image)
        XCTAssertTrue(sampler.isApproximately((0, 255, 0), atX: 100, y: 200),
                      "left of the seam should come from the green display")
        XCTAssertTrue(sampler.isApproximately((255, 0, 0), atX: 700, y: 200))
    }
}
