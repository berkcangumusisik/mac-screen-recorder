import AppKit
import XCTest
@testable import Snaplet

final class SensitiveDataDetectorTests: XCTestCase {

    private func kinds(_ text: String) -> [SensitiveDataDetector.Kind] {
        SensitiveDataDetector.matches(in: text).map(\.kind)
    }

    func testFindsEmailAddresses() {
        XCTAssertEqual(kinds("write to ada@example.com please"), [.email])
    }

    func testFindsTokenShapedStrings() {
        XCTAssertTrue(kinds("Authorization: Bearer abcdef0123456789ABCDEF").contains(.bearerToken))
        XCTAssertTrue(kinds("key=sk_live_51H8sPqXyZabcdefghij").contains(.apiKey))
        XCTAssertTrue(kinds("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N").contains(.jwt))
    }

    func testFindsAddressesAndLongNumbers() {
        XCTAssertTrue(kinds("host 192.168.1.244 is up").contains(.ipAddress))
        XCTAssertTrue(kinds("4111 1111 1111 1111").contains(.longNumber))
    }

    func testOrdinaryTextIsNotFlagged() {
        XCTAssertTrue(kinds("Open the settings window and press Save.").isEmpty)
        XCTAssertTrue(kinds("Version 2.1.4 released on the 3rd").isEmpty)
    }

    func testOverlappingMatchesAreReportedOnce() {
        // The JWT also looks key-like; only one suggestion should come back.
        let matches = SensitiveDataDetector.matches(in: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.aaaaaaaaaaaa")
        XCTAssertEqual(matches.count, 1)
    }

    func testMatchesAreReturnedInReadingOrder() {
        let matches = SensitiveDataDetector.matches(in: "a@b.com then 10.0.0.1")
        XCTAssertEqual(matches.map(\.kind), [.email, .ipAddress])
    }

    func testEmptyInputIsHandled() {
        XCTAssertTrue(SensitiveDataDetector.matches(in: "").isEmpty)
    }
}

final class TextRecognitionGeometryTests: XCTestCase {

    func testNormalisedBoxBecomesPixelsWithATopLeftOrigin() {
        let rect = TextRecognitionService.pixelRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1),
                                                    imageSize: CGSize(width: 1000, height: 800),
                                                    padding: 0)
        XCTAssertEqual(rect, CGRect(x: 250, y: 400, width: 500, height: 80))
    }

    func testPaddingNeverPushesTheRectOffTheImage() {
        let rect = TextRecognitionService.pixelRect(CGRect(x: 0, y: 0, width: 0.2, height: 0.05),
                                                    imageSize: CGSize(width: 400, height: 400),
                                                    padding: 0.05)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
    }
}

/// Runs Apple Vision over an image the test draws itself.
final class VisionRecognitionTests: XCTestCase {

    private func image(with text: String) -> CGImage {
        TestImages.make(width: 900, height: 220) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 220))
            context.translateBy(x: 0, y: 220)
            context.scaleBy(x: 1, y: -1)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            (text as NSString).draw(in: CGRect(x: 30, y: 70, width: 840, height: 90),
                                    withAttributes: [
                                        .font: NSFont.systemFont(ofSize: 56, weight: .medium),
                                        .foregroundColor: NSColor.black
                                    ])
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    func testRecognisesTextDrawnIntoAnImage() async throws {
        let result = try await TextRecognitionService().recognize(in: image(with: "Deploy failed"),
                                                                  languages: ["en-US"])
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.fullText.lowercased().contains("deploy"),
                      "recognised \(result.fullText)")
    }

    func testBoundingBoxesUseATopLeftOriginInsideTheImage() async throws {
        let result = try await TextRecognitionService().recognize(in: image(with: "Snaplet"),
                                                                  languages: ["en-US"])
        let line = try XCTUnwrap(result.lines.first)
        XCTAssertGreaterThanOrEqual(line.boundingBox.minX, 0)
        XCTAssertGreaterThanOrEqual(line.boundingBox.minY, 0)
        XCTAssertLessThanOrEqual(line.boundingBox.maxX, 1.001)
        XCTAssertLessThanOrEqual(line.boundingBox.maxY, 1.001)
    }

    func testSuggestsARegionForAnEmailAddress() async throws {
        let suggestions = try await TextRecognitionService()
            .sensitiveRegions(in: image(with: "ada@example.com"), languages: ["en-US"])
        XCTAssertTrue(suggestions.contains { $0.kind == .email },
                      "no email suggestion in \(suggestions.map(\.text))")
    }
}

final class BugReportTests: XCTestCase {

    func testMarkdownContainsEverySection() {
        var report = BugReport()
        report.title = "Selection overlay flickers"
        report.steps = "1. Press the shortcut"
        report.expected = "Overlay appears once"
        report.actual = "Overlay flickers twice"
        let markdown = report.markdown

        XCTAssertTrue(markdown.hasPrefix("# Selection overlay flickers"))
        XCTAssertTrue(markdown.contains("## Steps to reproduce"))
        XCTAssertTrue(markdown.contains("## Expected behavior"))
        XCTAssertTrue(markdown.contains("## Actual behavior"))
        XCTAssertTrue(markdown.contains("Overlay flickers twice"))
    }

    func testEnvironmentOnlyIncludesTickedItems() {
        var report = BugReport()
        report.includeSystemVersion = true
        report.includeAppVersion = false
        report.includeHardwareModel = false
        XCTAssertEqual(report.environmentPreview, BugReport.systemVersionLine)

        report.includeSystemVersion = false
        XCTAssertTrue(report.environmentPreview.isEmpty)
        XCTAssertFalse(report.markdown.contains("## Environment"))
    }

    func testEnvironmentNeverLeaksHostOrAccountNames() {
        var report = BugReport()
        report.includeSystemVersion = true
        report.includeAppVersion = true
        report.includeHardwareModel = true
        let preview = report.environmentPreview.lowercased()

        let hostName = Host.current().localizedName?.lowercased() ?? "###"
        let userName = NSUserName().lowercased()
        XCTAssertFalse(preview.contains(hostName))
        XCTAssertFalse(preview.contains(userName))
        XCTAssertFalse(preview.contains(NSHomeDirectory().lowercased()))
    }

    func testAttachmentsAreListedByNameWithAnExplicitUploadNote() {
        var report = BugReport()
        report.attachmentNames = ["Snaplet 2026-09-07 at 10.00.00.png"]
        let markdown = report.markdown
        XCTAssertTrue(markdown.contains("## Attachments"))
        XCTAssertTrue(markdown.contains("Snaplet 2026-09-07 at 10.00.00.png"))
        XCTAssertTrue(markdown.contains("has not uploaded them"))
        // Nothing that could be mistaken for a working GitHub media link.
        XCTAssertFalse(markdown.contains("https://"))
        XCTAssertFalse(markdown.contains("!["))
    }

    func testStepDraftMatchesTheNumberOfMarkers() {
        XCTAssertEqual(BugReport.stepDraft(markerCount: 0), "")
        XCTAssertEqual(BugReport.stepDraft(markerCount: 3), "1. \n2. \n3. ")
    }

    func testPlaceholdersAppearWhenFieldsAreBlank() {
        let markdown = BugReport().markdown
        XCTAssertTrue(markdown.hasPrefix("# Bug report"))
        XCTAssertTrue(markdown.contains("_Describe what you expected._"))
    }
}

final class CaptureRecordTests: XCTestCase {

    private func item(name: String, text: String) -> CaptureRecord {
        let item = CaptureRecord(path: "/tmp/\(name)",
                               fileName: name,
                               kind: .image,
                               createdAt: Date(),
                               pixelWidth: 100,
                               pixelHeight: 50,
                               fileSize: 1024)
        item.recognizedText = text
        return item
    }

    func testSearchMatchesFileNamesCaseInsensitively() {
        let subject = item(name: "Snaplet Login.png", text: "")
        XCTAssertTrue(subject.matches(query: "login"))
        XCTAssertFalse(subject.matches(query: "invoice"))
    }

    func testSearchMatchesRecognisedText() {
        let subject = item(name: "shot.png", text: "Build succeeded in 42 seconds")
        XCTAssertTrue(subject.matches(query: "succeeded"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(item(name: "a.png", text: "").matches(query: ""))
    }

    func testPixelDescriptionFallsBackWhenUnknown() {
        let subject = item(name: "a.png", text: "")
        XCTAssertEqual(subject.pixelDescription, "100 × 50")
        subject.pixelWidth = 0
        XCTAssertEqual(subject.pixelDescription, "—")
    }
}
