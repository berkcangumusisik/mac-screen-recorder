import XCTest
@testable import Snaplet

final class RenderTransformTests: XCTestCase {

    private func request(source: CGImage,
                         crop: CGRect,
                         turns: Int,
                         annotations: [Annotation] = []) -> RenderRequest {
        RenderRequest(source: source,
                      cropRect: crop,
                      quarterTurns: turns,
                      annotations: annotations,
                      style: nil,
                      scale: 2)
    }

    func testCropOnlyTranslatesCoordinates() {
        let image = TestImages.solid(width: 200, height: 100)
        let subject = request(source: image, crop: CGRect(x: 40, y: 20, width: 100, height: 50), turns: 0)
        XCTAssertEqual(subject.croppedPixelSize, CGSize(width: 100, height: 50))
        let mapped = CGPoint(x: 40, y: 20).applying(subject.sourceToOutput)
        XCTAssertEqual(mapped, CGPoint(x: 0, y: 0))
    }

    func testQuarterTurnSwapsOutputDimensions() {
        let image = TestImages.solid(width: 200, height: 100)
        let subject = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: 1)
        XCTAssertEqual(subject.croppedPixelSize, CGSize(width: 100, height: 200))
    }

    func testClockwiseRotationMovesTopLeftToTopRight() {
        let image = TestImages.solid(width: 200, height: 100)
        let subject = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: 1)
        let topLeft = CGPoint(x: 0, y: 0).applying(subject.sourceToOutput)
        XCTAssertEqual(topLeft.x, 100, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.001)
    }

    func testTwoQuarterTurnsMapCornersToOppositeCorners() {
        let image = TestImages.solid(width: 200, height: 100)
        let subject = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: 2)
        let mapped = CGPoint(x: 0, y: 0).applying(subject.sourceToOutput)
        XCTAssertEqual(mapped.x, 200, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 100, accuracy: 0.001)
    }

    func testThreeQuarterTurnsAreTheInverseOfOne() {
        let image = TestImages.solid(width: 200, height: 100)
        let subject = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: 3)
        let mapped = CGPoint(x: 0, y: 0).applying(subject.sourceToOutput)
        XCTAssertEqual(mapped.x, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 200, accuracy: 0.001)
    }

    func testNegativeTurnsNormalise() {
        let image = TestImages.solid(width: 200, height: 100)
        let minusOne = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: -1)
        let three = request(source: image, crop: CGRect(x: 0, y: 0, width: 200, height: 100), turns: 3)
        XCTAssertEqual(minusOne.sourceToOutput, three.sourceToOutput)
    }

    func testRotatedImageKeepsContentOnTheExpectedSide() throws {
        // Left half white, right half black. Rotating 90° clockwise should put
        // the white half on top.
        let image = TestImages.split(width: 100, height: 60)
        let rotated = try XCTUnwrap(AnnotationRenderer.rotate(image, quarterTurns: 1))
        XCTAssertEqual(rotated.width, 60)
        XCTAssertEqual(rotated.height, 100)
        let sampler = PixelSampler(rotated)
        XCTAssertTrue(sampler.isApproximately((255, 255, 255), atX: 30, y: 10),
                      "top of the rotated image should be the white half")
        XCTAssertTrue(sampler.isApproximately((0, 0, 0), atX: 30, y: 90),
                      "bottom of the rotated image should be the black half")
    }

    func testFlatRenderMatchesCroppedSize() throws {
        let image = TestImages.solid(width: 300, height: 200)
        let subject = request(source: image, crop: CGRect(x: 50, y: 25, width: 120, height: 80), turns: 0)
        let rendered = try XCTUnwrap(AnnotationRenderer.renderFlat(subject))
        XCTAssertEqual(rendered.width, 120)
        XCTAssertEqual(rendered.height, 80)
    }
}
