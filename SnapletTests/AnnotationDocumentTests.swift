import XCTest
@testable import Snaplet

@MainActor
final class AnnotationDocumentTests: XCTestCase {

    private func makeDocument() -> EditorDocument {
        EditorDocument(image: TestImages.solid(width: 400, height: 300),
                       scale: 2,
                       sourceURL: nil,
                       capturedAt: Date(timeIntervalSince1970: 0))
    }

    func testLineRecoversDirectionFromFlippedFlags() {
        let annotation = Annotation.line(kind: .arrow,
                                         from: CGPoint(x: 200, y: 150),
                                         to: CGPoint(x: 50, y: 40))
        XCTAssertEqual(annotation.startPoint, CGPoint(x: 200, y: 150))
        XCTAssertEqual(annotation.endPoint, CGPoint(x: 50, y: 40))
        XCTAssertEqual(annotation.frame, CGRect(x: 50, y: 40, width: 150, height: 110))
    }

    func testStepNumbersAreRenumberedAfterADelete() {
        let document = makeDocument()
        for _ in 0..<3 {
            document.add(document.makeAnnotation(kind: .step, frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        }
        XCTAssertEqual(document.annotations.map(\.number), [1, 2, 3])

        document.selectedID = document.annotations[1].id
        document.deleteSelected()
        XCTAssertEqual(document.annotations.map(\.number), [1, 2])
        XCTAssertEqual(document.nextStepNumber, 3)
    }

    func testUndoRestoresAnnotationsCropAndRotation() {
        let document = makeDocument()
        document.add(document.makeAnnotation(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 50, height: 50)))
        document.applyCrop(CGRect(x: 20, y: 20, width: 200, height: 100))
        document.rotate(by: 1)

        XCTAssertEqual(document.quarterTurns, 1)
        document.undo()
        XCTAssertEqual(document.quarterTurns, 0)
        document.undo()
        XCTAssertEqual(document.cropRect, document.fullRect)
        document.undo()
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo)
    }

    func testRedoReappliesAnUndoneChange() {
        let document = makeDocument()
        document.rotate(by: 1)
        document.undo()
        XCTAssertTrue(document.canRedo)
        document.redo()
        XCTAssertEqual(document.quarterTurns, 1)
    }

    func testCropIsClampedToTheImageAndRejectsTinyRects() {
        let document = makeDocument()
        document.applyCrop(CGRect(x: -100, y: -100, width: 10_000, height: 10_000))
        XCTAssertEqual(document.cropRect, document.fullRect)

        let before = document.cropRect
        document.applyCrop(CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(document.cropRect, before)
    }

    func testRotationWrapsAroundFourQuarterTurns() {
        let document = makeDocument()
        document.rotate(by: 3)
        document.rotate(by: 3)
        XCTAssertEqual(document.quarterTurns, 2)
        document.rotate(by: -2)
        XCTAssertEqual(document.quarterTurns, 0)
    }

    func testApplyingAStyleKeepsAnExistingCaption() {
        let document = makeDocument()
        var preset = StylePreset.clean
        preset.title = "Step one"
        document.applyStyle(preset)
        document.applyStyle(.midnight)
        XCTAssertEqual(document.style?.id, "midnight")
        XCTAssertEqual(document.style?.title, "Step one")
    }

    func testDeletingClearsTheSelection() {
        let document = makeDocument()
        document.add(document.makeAnnotation(kind: .ellipse, frame: CGRect(x: 0, y: 0, width: 30, height: 30)))
        XCTAssertNotNil(document.selectedID)
        document.deleteSelected()
        XCTAssertNil(document.selectedID)
    }
}

@MainActor
final class EditorZoomTests: XCTestCase {

    private func makeDocument() -> EditorDocument {
        EditorDocument(image: TestImages.solid(width: 400, height: 300),
                       scale: 2,
                       sourceURL: nil,
                       capturedAt: Date(timeIntervalSince1970: 0))
    }

    func testTheEditorOpensFittedToTheWindow() {
        XCTAssertEqual(makeDocument().zoom, 0)
        // Compared against the localised string: the test host may run in any language.
        XCTAssertEqual(makeDocument().zoomDescription, String(localized: "Fit"))
    }

    func testZoomingInStepsUpFromWhatIsOnScreen() {
        let document = makeDocument()
        // Fitted at 40%, so the first step in is the next stop above it.
        document.effectiveZoom = 0.4
        document.zoomIn()
        XCTAssertEqual(document.zoom, 0.5)
        document.effectiveZoom = 0.5
        document.zoomIn()
        XCTAssertEqual(document.zoom, 0.67)
    }

    func testZoomingOutStepsDown() {
        let document = makeDocument()
        document.effectiveZoom = 1
        document.zoomOut()
        XCTAssertEqual(document.zoom, 0.67)
    }

    func testZoomStopsAtTheEndsInsteadOfRunningAway() {
        let document = makeDocument()
        document.effectiveZoom = 4
        document.zoomIn()
        XCTAssertEqual(document.zoom, 4, "already at the largest step")

        document.effectiveZoom = 0.25
        document.zoomOut()
        XCTAssertEqual(document.zoom, 0.25, "already at the smallest step")
    }

    func testFitAndActualSizeAreDistinctStates() {
        let document = makeDocument()
        document.zoomToActualSize()
        XCTAssertEqual(document.zoom, 1)
        XCTAssertEqual(document.zoomDescription, "100%")

        document.zoomToFit()
        XCTAssertEqual(document.zoom, 0)
        XCTAssertEqual(document.zoomDescription, String(localized: "Fit"))
    }

    func testZoomDescriptionRoundsToWholePercent() {
        let document = makeDocument()
        document.zoom = 0.67
        XCTAssertEqual(document.zoomDescription, "67%")
    }
}
