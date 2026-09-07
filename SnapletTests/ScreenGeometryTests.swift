import XCTest
@testable import Snaplet

final class ScreenGeometryTests: XCTestCase {

    func testAppKitToCoreGraphicsIsAnInvolution() {
        let geometry = ScreenGeometry(primaryHeight: 1080)
        let rect = CGRect(x: 120, y: 340, width: 400, height: 260)
        let converted = geometry.cgRect(fromAppKit: rect)
        XCTAssertEqual(geometry.appKitRect(fromCG: converted), rect)
    }

    func testTopLeftOfPrimaryDisplayMapsToOrigin() {
        let geometry = ScreenGeometry(primaryHeight: 900)
        // AppKit point at the very top-left of the primary display.
        let point = CGPoint(x: 0, y: 900)
        XCTAssertEqual(geometry.cgPoint(fromAppKit: point), CGPoint(x: 0, y: 0))
    }

    func testPixelCropOnRetinaPrimaryDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 100, y: 700, width: 200, height: 100)
        let crop = ScreenGeometry.pixelCropRect(selection: selection,
                                                inDisplayFrame: display,
                                                scale: 2,
                                                imagePixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(crop, CGRect(x: 200, y: 200, width: 400, height: 200))
    }

    func testPixelCropOnSecondaryDisplayUsesDisplayLocalCoordinates() {
        let display = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 1540, y: 100, width: 100, height: 50)
        let crop = ScreenGeometry.pixelCropRect(selection: selection,
                                                inDisplayFrame: display,
                                                scale: 1,
                                                imagePixelSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(crop, CGRect(x: 100, y: 930, width: 100, height: 50))
    }

    func testPixelCropOnDisplayWithNegativeOrigin() {
        // A display placed to the left of and below the primary one.
        let display = CGRect(x: -1680, y: -300, width: 1680, height: 1050)
        let selection = CGRect(x: -1600, y: 600, width: 200, height: 100)
        let crop = ScreenGeometry.pixelCropRect(selection: selection,
                                                inDisplayFrame: display,
                                                scale: 2,
                                                imagePixelSize: CGSize(width: 3360, height: 2100))
        // localMinX = 80, localMinY = 750 - 700 = 50
        XCTAssertEqual(crop, CGRect(x: 160, y: 100, width: 400, height: 200))
    }

    func testPixelCropClampsToImageBounds() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let selection = CGRect(x: -50, y: -50, width: 200, height: 200)
        let crop = ScreenGeometry.pixelCropRect(selection: selection,
                                                inDisplayFrame: display,
                                                scale: 1,
                                                imagePixelSize: CGSize(width: 1000, height: 1000))
        XCTAssertNotNil(crop)
        let unwrapped = try! XCTUnwrap(crop)
        XCTAssertGreaterThanOrEqual(unwrapped.minX, 0)
        XCTAssertGreaterThanOrEqual(unwrapped.minY, 0)
        XCTAssertLessThanOrEqual(unwrapped.maxX, 1000)
        XCTAssertLessThanOrEqual(unwrapped.maxY, 1000)
    }

    func testPixelCropRejectsEmptySelection() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertNil(ScreenGeometry.pixelCropRect(selection: CGRect(x: 10, y: 10, width: 0, height: 0),
                                                  inDisplayFrame: display,
                                                  scale: 2,
                                                  imagePixelSize: CGSize(width: 2000, height: 2000)))
    }

    func testPixelCropRejectsSelectionCompletelyOutsideDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertNil(ScreenGeometry.pixelCropRect(selection: CGRect(x: 2000, y: 2000, width: 100, height: 100),
                                                  inDisplayFrame: display,
                                                  scale: 1,
                                                  imagePixelSize: CGSize(width: 1000, height: 1000)))
    }

    func testRectFromTwoPointsIsAlwaysPositive() {
        let rect = ScreenGeometry.rect(from: CGPoint(x: 300, y: 400), to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 200, height: 300))
    }
}
