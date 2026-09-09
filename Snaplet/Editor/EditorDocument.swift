import AppKit
import Combine

/// The editable state of one image.
///
/// The source image is immutable. Cropping, rotation and every annotation are
/// stored separately and applied at render time, so any edit can be undone and
/// the original pixels are always available until the user exports.
@MainActor
final class EditorDocument: ObservableObject {

    let sourceImage: CGImage
    let scale: CGFloat
    let capturedAt: Date
    var sourceURL: URL?

    @Published var cropRect: CGRect
    @Published var quarterTurns: Int = 0
    @Published var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var style: StylePreset?

    // Current tool settings, shared by newly created annotations.
    @Published var tool: EditorTool = .select
    @Published var strokeColor = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    @Published var fillEnabled = false
    @Published var fillColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.85)
    @Published var lineWidth: Double = 6
    @Published var fontSize: Double = 36
    @Published var effectStrength: Double = 20

    /// Points shown per source point. 0 means "fit the window", which is the
    /// state the editor opens in and returns to with ⌘0.
    @Published var zoom: Double = 0

    /// Steps the keyboard and the zoom menu move between.
    static let zoomSteps: [Double] = [0.25, 0.33, 0.5, 0.67, 1, 1.5, 2, 3, 4]

    var zoomDescription: String {
        zoom <= 0 ? String(localized: "Fit") : "\(Int((zoom * 100).rounded()))%"
    }

    func zoomIn() { zoom = Self.zoomSteps.first { $0 > effectiveZoom } ?? Self.zoomSteps.last! }

    func zoomOut() { zoom = Self.zoomSteps.last { $0 < effectiveZoom } ?? Self.zoomSteps.first! }

    func zoomToFit() { zoom = 0 }

    func zoomToActualSize() { zoom = 1 }

    /// The factor currently on screen. Reported by the canvas so stepping from
    /// "fit" continues from what the user can actually see.
    @Published var effectiveZoom: Double = 1

    private struct Snapshot: Equatable {
        var annotations: [Annotation]
        var cropRect: CGRect
        var quarterTurns: Int
        var style: StylePreset?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(image: CGImage, scale: CGFloat, sourceURL: URL?, capturedAt: Date) {
        self.sourceImage = image
        self.scale = scale > 0 ? scale : 2
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt
        self.cropRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    var fullRect: CGRect {
        CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    }

    var isCropped: Bool { cropRect.integral != fullRect }

    var renderRequest: RenderRequest {
        RenderRequest(source: sourceImage,
                      cropRect: cropRect.integral.intersection(fullRect),
                      quarterTurns: quarterTurns,
                      annotations: annotations,
                      style: style,
                      scale: scale)
    }

    var selectedAnnotation: Annotation? {
        guard let selectedID else { return nil }
        return annotations.first { $0.id == selectedID }
    }

    // MARK: - Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var snapshot: Snapshot {
        Snapshot(annotations: annotations, cropRect: cropRect, quarterTurns: quarterTurns, style: style)
    }

    /// Call once before a logical change — a whole drag counts as one change.
    func checkpoint() {
        undoStack.append(snapshot)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        quarterTurns = snapshot.quarterTurns
        style = snapshot.style
        if let selectedID, !annotations.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    // MARK: - Annotations

    func makeAnnotation(kind: Annotation.Kind, frame: CGRect) -> Annotation {
        var annotation = Annotation(kind: kind, frame: frame)
        annotation.strokeColor = strokeColor
        annotation.fillColor = fillEnabled ? fillColor : nil
        annotation.lineWidth = lineWidth
        annotation.fontSize = fontSize
        annotation.effectStrength = effectStrength
        if kind == .step {
            annotation.number = nextStepNumber
            annotation.fillColor = nil
        }
        if kind == .redaction {
            annotation.strokeColor = RGBAColor(red: 0.06, green: 0.06, blue: 0.07)
        }
        if kind == .callout {
            annotation.fillColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.96)
            annotation.text = String(localized: "Double-click to edit")
        }
        if kind == .text {
            annotation.text = String(localized: "Text")
            annotation.fillColor = nil
        }
        return annotation
    }

    var nextStepNumber: Int {
        (annotations.filter { $0.kind == .step }.map(\.number).max() ?? 0) + 1
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        selectedID = annotation.id
    }

    func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    func deleteSelected() {
        guard let selectedID else { return }
        checkpoint()
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
        renumberSteps()
    }

    func bringSelectedToFront() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        checkpoint()
        let annotation = annotations.remove(at: index)
        annotations.append(annotation)
    }

    /// Keeps step markers reading 1, 2, 3… in creation order after a delete.
    func renumberSteps() {
        var counter = 1
        for index in annotations.indices where annotations[index].kind == .step {
            annotations[index].number = counter
            counter += 1
        }
    }

    // MARK: - Geometry

    func rotate(by turns: Int) {
        checkpoint()
        quarterTurns = (((quarterTurns + turns) % 4) + 4) % 4
    }

    func applyCrop(_ rect: CGRect) {
        let clamped = rect.integral.intersection(fullRect)
        guard clamped.width >= 8, clamped.height >= 8 else { return }
        checkpoint()
        cropRect = clamped
    }

    func resetCrop() {
        guard isCropped else { return }
        checkpoint()
        cropRect = fullRect
    }

    // MARK: - Rendering

    func renderedImage() -> CGImage? {
        AnnotationRenderer.render(renderRequest)
    }

    /// Applies a preset while keeping any caption the user already typed.
    func applyStyle(_ preset: StylePreset?) {
        checkpoint()
        guard var preset else {
            style = nil
            return
        }
        if let existing = style {
            preset.title = existing.title
            preset.subtitle = existing.subtitle
        }
        style = preset
    }
}
