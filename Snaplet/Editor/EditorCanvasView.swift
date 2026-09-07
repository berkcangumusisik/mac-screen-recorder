import AppKit
import Combine
import SwiftUI

/// Draws the document and handles direct manipulation.
///
/// The view's bounds are always exactly the displayed image, so mapping between
/// view points and source pixels is a single uniform scale composed with the
/// document's crop/rotation transform.
final class EditorCanvasView: NSView {

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .top: return CGPoint(x: rect.midX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .right: return CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .left: return CGPoint(x: rect.minX, y: rect.midY)
            }
        }

        func resize(_ rect: CGRect, to point: CGPoint) -> CGRect {
            var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
            switch self {
            case .topLeft: minX = point.x; minY = point.y
            case .top: minY = point.y
            case .topRight: maxX = point.x; minY = point.y
            case .right: maxX = point.x
            case .bottomRight: maxX = point.x; maxY = point.y
            case .bottom: maxY = point.y
            case .bottomLeft: minX = point.x; maxY = point.y
            case .left: minX = point.x
            }
            return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
        }
    }

    let document: EditorDocument
    /// Crop rectangle being edited, in source pixels. Non-nil only in crop mode.
    private(set) var cropDraft: CGRect?

    private var cancellable: AnyCancellable?
    private var dragStart: CGPoint?
    private var draftID: UUID?
    private var activeHandle: Handle?
    private var frameAtDragStart: CGRect?
    private var pointsAtDragStart: [CGPoint] = []
    private var isDraggingCrop = false

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        cancellable = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncCropDraft(); self?.needsDisplay = true }
        }
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Editing canvas"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func syncCropDraft() {
        if document.tool == .crop {
            if cropDraft == nil { cropDraft = document.cropRect }
        } else {
            cropDraft = nil
        }
    }

    // MARK: - Coordinate mapping

    private var outputPixelSize: CGSize { document.renderRequest.croppedPixelSize }

    /// source pixels -> view points
    private var viewTransform: CGAffineTransform {
        let output = outputPixelSize
        guard output.width > 0, output.height > 0, bounds.width > 0 else { return .identity }
        let k = bounds.width / output.width
        return document.renderRequest.sourceToOutput.concatenating(CGAffineTransform(scaleX: k, y: k))
    }

    private func sourcePoint(from viewPoint: CGPoint) -> CGPoint {
        viewPoint.applying(viewTransform.inverted())
    }

    private func viewRect(fromSource rect: CGRect) -> CGRect {
        rect.applying(viewTransform)
    }

    /// Points per source pixel, used to keep handles the same on-screen size.
    private var displayScale: CGFloat {
        let output = outputPixelSize
        guard output.width > 0 else { return 1 }
        return bounds.width / output.width
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let output = outputPixelSize
        guard output.width > 0, output.height > 0 else { return }

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let request = document.renderRequest
        context.saveGState()
        context.interpolationQuality = .high
        let k = displayScale
        context.scaleBy(x: k, y: k)

        if let cropped = request.source.cropping(to: request.cropRect.integral),
           let rotated = AnnotationRenderer.rotate(cropped, quarterTurns: request.quarterTurns) {
            NSImage(cgImage: rotated, size: output).draw(in: CGRect(origin: .zero, size: output))
        }

        context.concatenate(request.sourceToOutput)
        AnnotationRenderer.drawAnnotations(request.annotations, source: request.source)
        context.restoreGState()

        drawCropOverlay()
        drawSelectionHandles()
    }

    private func drawCropOverlay() {
        guard document.tool == .crop, let cropDraft else { return }
        let rect = viewRect(fromSource: cropDraft)
        NSColor.black.withAlphaComponent(0.45).setFill()
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: rect).reversed)
        path.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        border.stroke()
        drawHandles(for: rect)
    }

    private func drawSelectionHandles() {
        guard document.tool != .crop,
              let selected = document.selectedAnnotation else { return }
        let rect = viewRect(fromSource: selected.frame).insetBy(dx: -3, dy: -3)
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.setLineDash([4, 3], count: 2, phase: 0)
        border.stroke()
        if !selected.kind.isPathBased {
            drawHandles(for: rect)
        }
    }

    private func drawHandles(for rect: CGRect) {
        let size: CGFloat = 8
        for handle in Handle.allCases {
            let point = handle.point(in: rect)
            let box = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: box).fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(ovalIn: box)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = sourcePoint(from: viewPoint)
        dragStart = point

        if document.tool == .crop {
            beginCropDrag(at: viewPoint, source: point)
            return
        }

        if event.clickCount == 2, let hit = annotation(at: point), hit.kind == .text || hit.kind == .callout {
            document.selectedID = hit.id
            NotificationCenter.default.post(name: .snapletEditTextRequested, object: hit.id)
            return
        }

        if let kind = document.tool.annotationKind {
            beginNewAnnotation(kind: kind, at: point)
            return
        }

        // Select tool: handles first, then hit testing.
        if let selected = document.selectedAnnotation, !selected.kind.isPathBased,
           let handle = handle(at: viewPoint, for: selected.frame) {
            document.checkpoint()
            activeHandle = handle
            frameAtDragStart = selected.frame
            draftID = selected.id
            return
        }
        if let hit = annotation(at: point) {
            document.checkpoint()
            document.selectedID = hit.id
            draftID = hit.id
            frameAtDragStart = hit.frame
            pointsAtDragStart = hit.points
        } else {
            document.selectedID = nil
            draftID = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = sourcePoint(from: viewPoint)
        guard let dragStart else { return }

        if document.tool == .crop {
            if isDraggingCrop {
                if let handle = activeHandle, let frameAtDragStart {
                    cropDraft = handle.resize(frameAtDragStart, to: point).intersection(document.fullRect)
                } else {
                    cropDraft = ScreenGeometry.rect(from: dragStart, to: point).intersection(document.fullRect)
                }
                needsDisplay = true
            }
            return
        }

        guard let draftID,
              var annotation = document.annotations.first(where: { $0.id == draftID }) else { return }

        if document.tool.annotationKind != nil {
            update(&annotation, dragStart: dragStart, current: point, modifiers: event.modifierFlags)
        } else if let handle = activeHandle, let frameAtDragStart {
            annotation.frame = handle.resize(frameAtDragStart, to: point)
        } else if let frameAtDragStart {
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            annotation.frame = frameAtDragStart.offsetBy(dx: dx, dy: dy)
            if !pointsAtDragStart.isEmpty {
                annotation.points = pointsAtDragStart.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        }
        document.replace(annotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if document.tool == .crop {
            isDraggingCrop = false
            activeHandle = nil
            frameAtDragStart = nil
            dragStart = nil
            return
        }
        if let draftID, let annotation = document.annotations.first(where: { $0.id == draftID }) {
            // Discard degenerate shapes created by a stray click.
            let isTiny = annotation.frame.width < 3 && annotation.frame.height < 3
            let isEmptyPath = annotation.kind.isPathBased && annotation.points.count < 2
            if document.tool.annotationKind != nil,
               annotation.kind != .step, annotation.kind != .text,
               isTiny || isEmptyPath {
                document.annotations.removeAll { $0.id == draftID }
                document.selectedID = nil
            }
        }
        dragStart = nil
        draftID = nil
        activeHandle = nil
        frameAtDragStart = nil
        pointsAtDragStart = []
        needsDisplay = true
    }

    // MARK: - Interaction helpers

    /// Dragging a handle resizes the current crop; dragging anywhere else
    /// starts a new one.
    private func beginCropDrag(at viewPoint: CGPoint, source point: CGPoint) {
        isDraggingCrop = true
        if let cropDraft, let handle = handle(at: viewPoint, for: cropDraft) {
            activeHandle = handle
            frameAtDragStart = cropDraft
            return
        }
        activeHandle = nil
        frameAtDragStart = nil
    }

    private func beginNewAnnotation(kind: Annotation.Kind, at point: CGPoint) {
        var annotation: Annotation
        switch kind {
        case .step:
            let diameter = max(36, document.lineWidth * 8)
            annotation = document.makeAnnotation(kind: .step,
                                                 frame: CGRect(x: point.x - diameter / 2,
                                                               y: point.y - diameter / 2,
                                                               width: diameter,
                                                               height: diameter))
        case .text:
            let width = document.fontSize * 9
            annotation = document.makeAnnotation(kind: .text,
                                                 frame: CGRect(x: point.x,
                                                               y: point.y,
                                                               width: width,
                                                               height: document.fontSize * 1.4))
        default:
            annotation = document.makeAnnotation(kind: kind, frame: CGRect(origin: point, size: .zero))
            if kind.isPathBased { annotation.points = [point] }
            if kind == .callout { annotation.points = [CGPoint(x: point.x, y: point.y + 80)] }
        }
        document.add(annotation)
        draftID = annotation.id
        frameAtDragStart = annotation.frame
    }

    private func update(_ annotation: inout Annotation,
                        dragStart: CGPoint,
                        current: CGPoint,
                        modifiers: NSEvent.ModifierFlags) {
        switch annotation.kind {
        case .freehand, .highlighter:
            annotation.points.append(current)
            let xs = annotation.points.map(\.x)
            let ys = annotation.points.map(\.y)
            let inset = annotation.lineWidth / 2
            annotation.frame = CGRect(x: (xs.min() ?? 0) - inset,
                                      y: (ys.min() ?? 0) - inset,
                                      width: (xs.max() ?? 0) - (xs.min() ?? 0) + inset * 2,
                                      height: (ys.max() ?? 0) - (ys.min() ?? 0) + inset * 2)
        case .arrow, .line:
            var end = current
            if modifiers.contains(.shift) {
                // Snap to 15° increments for tidy diagrams.
                let angle = atan2(end.y - dragStart.y, end.x - dragStart.x)
                let step = CGFloat.pi / 12
                let snapped = (angle / step).rounded() * step
                let length = hypot(end.x - dragStart.x, end.y - dragStart.y)
                end = CGPoint(x: dragStart.x + cos(snapped) * length,
                              y: dragStart.y + sin(snapped) * length)
            }
            let replacement = Annotation.line(kind: annotation.kind, from: dragStart, to: end)
            annotation.frame = replacement.frame
            annotation.isFlippedHorizontally = replacement.isFlippedHorizontally
            annotation.isFlippedVertically = replacement.isFlippedVertically
        case .step, .text:
            annotation.frame.origin = CGPoint(x: current.x - annotation.frame.width / 2,
                                              y: current.y - annotation.frame.height / 2)
        default:
            var rect = ScreenGeometry.rect(from: dragStart, to: current)
            if modifiers.contains(.shift) {
                let side = max(rect.width, rect.height)
                rect = CGRect(x: current.x < dragStart.x ? dragStart.x - side : dragStart.x,
                              y: current.y < dragStart.y ? dragStart.y - side : dragStart.y,
                              width: side, height: side)
            }
            annotation.frame = rect
        }
    }

    private func annotation(at point: CGPoint) -> Annotation? {
        let padding = 8 / max(displayScale, 0.05)
        return document.annotations.reversed().first { $0.hitRect(padding: padding).contains(point) }
    }

    private func handle(at viewPoint: CGPoint, for sourceRect: CGRect) -> Handle? {
        let rect = viewRect(fromSource: sourceRect).insetBy(dx: -3, dy: -3)
        return Handle.allCases.first { handle in
            let point = handle.point(in: rect)
            return hypot(point.x - viewPoint.x, point.y - viewPoint.y) <= 9
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete / Forward delete
            document.deleteSelected()
        case 53: // Escape
            if document.tool == .crop {
                cropDraft = document.cropRect
                needsDisplay = true
            } else {
                document.selectedID = nil
            }
        case 36, 76: // Return
            if document.tool == .crop, let cropDraft {
                document.applyCrop(cropDraft)
                document.tool = .select
            }
        case 123, 124, 125, 126: // Arrows nudge the selection
            nudge(event)
        default:
            super.keyDown(with: event)
        }
    }

    private func nudge(_ event: NSEvent) {
        guard var annotation = document.selectedAnnotation else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var delta = CGPoint.zero
        switch event.keyCode {
        case 123: delta.x = -step
        case 124: delta.x = step
        case 125: delta.y = step
        case 126: delta.y = -step
        default: return
        }
        document.checkpoint()
        annotation.frame = annotation.frame.offsetBy(dx: delta.x, dy: delta.y)
        annotation.points = annotation.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        document.replace(annotation)
        needsDisplay = true
    }

    func applyCropDraft() {
        guard let cropDraft else { return }
        document.applyCrop(cropDraft)
    }
}

extension Notification.Name {
    static let snapletEditTextRequested = Notification.Name("app.snaplet.editTextRequested")
}

/// Keeps the canvas centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let documentFrame = documentView.frame
        if rect.width > documentFrame.width {
            rect.origin.x = (documentFrame.width - rect.width) / 2
        }
        if rect.height > documentFrame.height {
            rect.origin.y = (documentFrame.height - rect.height) / 2
        }
        return rect
    }
}

/// SwiftUI wrapper that owns the scroll view and keeps the canvas sized.
struct EditorCanvas: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    var zoom: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.allowsMagnification = false

        let canvas = EditorCanvasView(document: document)
        scrollView.documentView = canvas
        context.coordinator.canvas = canvas
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }
        let output = document.renderRequest.croppedPixelSize
        guard output.width > 0, output.height > 0 else { return }
        let natural = CGSize(width: output.width / document.scale, height: output.height / document.scale)
        let visible = scrollView.contentView.bounds.size

        let factor: CGFloat
        if zoom <= 0 {
            let fit = min(visible.width / natural.width, visible.height / natural.height)
            factor = min(1, max(0.05, fit.isFinite ? fit : 1))
        } else {
            factor = CGFloat(zoom)
        }
        let size = CGSize(width: (natural.width * factor).rounded(),
                          height: (natural.height * factor).rounded())
        if canvas.frame.size != size {
            canvas.setFrameSize(size)
        }
        canvas.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var canvas: EditorCanvasView?
    }
}
