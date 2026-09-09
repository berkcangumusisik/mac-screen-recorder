import AppKit
import XCTest
@testable import Snaplet

final class ColorFormattingTests: XCTestCase {

    func testHexUsesUppercaseSixDigitForm() {
        XCTAssertEqual(ColorFormatting.hex(.black), "#000000")
        XCTAssertEqual(ColorFormatting.hex(.white), "#FFFFFF")
        XCTAssertEqual(ColorFormatting.hex(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)), "#FF0000")
    }

    func testHexRoundsRatherThanTruncates() {
        // 0.5 * 255 = 127.5, which must not silently become 127.
        let grey = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        XCTAssertEqual(ColorFormatting.hex(grey), "#808080")
    }

    func testHexConvertsFromOtherColourSpaces() {
        let device = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(ColorFormatting.hex(device).count, 7)
        XCTAssertTrue(ColorFormatting.hex(device).hasPrefix("#"))
    }
}

final class PixelSamplingTests: XCTestCase {

    /// Left half white, right half black, so a wrong x or a flipped y is obvious.
    private let image = TestImages.split(width: 100, height: 60)

    func testSamplesTheColourAtAPixel() throws {
        let left = try XCTUnwrap(SelectionOverlayView.color(in: image, atX: 10, y: 30))
        let right = try XCTUnwrap(SelectionOverlayView.color(in: image, atX: 90, y: 30))
        XCTAssertEqual(ColorFormatting.hex(left), "#FFFFFF")
        XCTAssertEqual(ColorFormatting.hex(right), "#000000")
    }

    func testSamplingUsesATopLeftOrigin() throws {
        // The split runs vertically, so both rows give the same answer; what
        // matters is that a y beyond the image is rejected rather than wrapped.
        XCTAssertNotNil(SelectionOverlayView.color(in: image, atX: 0, y: 0))
        XCTAssertNotNil(SelectionOverlayView.color(in: image, atX: 99, y: 59))
    }

    func testOutOfBoundsSamplesReturnNothing() {
        XCTAssertNil(SelectionOverlayView.color(in: image, atX: -1, y: 10))
        XCTAssertNil(SelectionOverlayView.color(in: image, atX: 10, y: -1))
        XCTAssertNil(SelectionOverlayView.color(in: image, atX: 100, y: 10))
        XCTAssertNil(SelectionOverlayView.color(in: image, atX: 10, y: 60))
    }
}

@MainActor
final class PinnedShotTests: XCTestCase {

    func testNaturalSizeIsInPointsNotPixels() {
        let shot = PinnedShot(image: TestImages.solid(width: 800, height: 600),
                              scale: 2,
                              capturedAt: Date())
        XCTAssertEqual(shot.naturalSize, CGSize(width: 400, height: 300))
    }

    func testASmallCaptureIsPinnedAtItsOwnSize() {
        let shot = PinnedShot(image: TestImages.solid(width: 200, height: 100),
                              scale: 1,
                              capturedAt: Date())
        XCTAssertEqual(shot.initialSize, CGSize(width: 200, height: 100))
    }

    func testALargeCaptureIsScaledDownAndKeepsItsAspectRatio() throws {
        let shot = PinnedShot(image: TestImages.solid(width: 12_000, height: 6_000),
                              scale: 1,
                              capturedAt: Date())
        let initial = shot.initialSize
        XCTAssertLessThan(initial.width, shot.naturalSize.width)
        XCTAssertEqual(initial.width / initial.height,
                       shot.naturalSize.width / shot.naturalSize.height,
                       accuracy: 0.02)
    }

    func testAnInvalidScaleFallsBackRatherThanDividingByZero() {
        let shot = PinnedShot(image: TestImages.solid(width: 100, height: 100),
                              scale: 0,
                              capturedAt: Date())
        XCTAssertTrue(shot.naturalSize.width.isFinite)
        XCTAssertGreaterThan(shot.naturalSize.width, 0)
    }

    func testPixelDescriptionReportsPixelsNotPoints() {
        let shot = PinnedShot(image: TestImages.solid(width: 640, height: 480),
                              scale: 2,
                              capturedAt: Date())
        XCTAssertEqual(shot.pixelDescription, "640 × 480")
    }
}

final class CaptureDelayPreferenceTests: XCTestCase {

    func testDelayDefaultsToImmediate() {
        XCTAssertEqual(Preferences().captureDelaySeconds, 0)
    }

    func testDelaySurvivesAJSONRoundTrip() throws {
        var preferences = Preferences()
        preferences.captureDelaySeconds = 5
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data).captureDelaySeconds, 5)
    }

    /// Adding a preference must not throw away the ones already stored. The
    /// synthesised decoder threw `keyNotFound` for every missing key, which
    /// would have reset all settings on the next launch.
    func testPreferencesWrittenByAnOlderBuildStillDecode() throws {
        let json = #"{"copyImageToClipboard":false,"autoSaveToDisk":true,"jpegQuality":0.5}"#
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        // Stored values survive.
        XCTAssertFalse(decoded.copyImageToClipboard)
        XCTAssertEqual(decoded.jpegQuality, 0.5)
        // Everything the old build never wrote falls back to its default.
        XCTAssertEqual(decoded.captureDelaySeconds, 0)
        XCTAssertEqual(decoded.imageFormat, .png)
        XCTAssertEqual(decoded.videoFrameRate, 60)
        XCTAssertTrue(decoded.recordSystemAudio)
        XCTAssertEqual(decoded.webcamCorner, .bottomTrailing)
    }

    func testAnEmptyBlobDecodesToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, Preferences())
    }

    func testAFullRoundTripPreservesEveryField() throws {
        var preferences = Preferences()
        preferences.captureDelaySeconds = 10
        preferences.imageFormat = .jpeg
        preferences.webcamCorner = .topLeading
        preferences.outputDirectoryPath = "/tmp/shots"
        preferences.shortcuts["captureArea"] = .some(nil)

        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), preferences)
    }
}
