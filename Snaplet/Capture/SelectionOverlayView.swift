import AppKit

/// Draws the dimmed snapshot, the live selection and the pixel loupe for a
/// single display. All coordinates in this view are AppKit points local to the
/// display; the controller converts them to global coordinates.
final class SelectionOverlayView: NSView {

    weak var controller: SelectionOverlayController?
    let snapshot: DisplaySnapshot
    var mode: SelectionOverlayController.Mode
    /// Window candidates whose frames intersect this display, front to back.
    var candidates: [WindowCandidate] = []

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let infoLayer = CATextLayer()
    private let hintLayer = CATextLayer()
    private let loupeLayer = CALayer()
    private let loupeContent = CALayer()
    private let loupeCrosshair = CAShapeLayer()
    private let loupeReadout = CATextLayer()

    private var anchorPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isMovingSelection = false
    private var moveOrigin: CGPoint?
    private var movedRectAtStart: CGRect?
    private var hoveredCandidate: WindowCandidate?
    private var trackingArea: NSTrackingArea?

    private static let loupeSide: CGFloat = 152
    private static let loupeSourcePixels: CGFloat = 30

    init(snapshot: DisplaySnapshot, mode: SelectionOverlayController.Mode) {
        self.snapshot = snapshot
        self.mode = mode
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        wantsLayer = true
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Layers

    private func configureLayers() {
        guard let root = layer else { return }
        root.backgroundColor = NSColor.clear.cgColor

        imageLayer.contents = NSImage(cgImage: snapshot.image, size: snapshot.frame.size)
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds
        root.addSublayer(imageLayer)

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dimLayer.frame = bounds
        root.addSublayer(dimLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.6
        borderLayer.shadowRadius = 1
        borderLayer.shadowOffset = .zero
        borderLayer.frame = bounds
        root.addSublayer(borderLayer)

        styleText(infoLayer, fontSize: 12)
        infoLayer.isHidden = true
        root.addSublayer(infoLayer)

        styleText(hintLayer, fontSize: 12)
        hintLayer.alignmentMode = .center
        root.addSublayer(hintLayer)

        loupeLayer.frame = CGRect(x: 0, y: 0, width: Self.loupeSide, height: Self.loupeSide + 22)
        loupeLayer.isHidden = true
        loupeLayer.masksToBounds = false

        loupeContent.frame = CGRect(x: 0, y: 22, width: Self.loupeSide, height: Self.loupeSide)
        loupeContent.magnificationFilter = .nearest
        loupeContent.minificationFilter = .nearest
        loupeContent.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        loupeContent.borderWidth = 1
        loupeContent.masksToBounds = true
        loupeContent.backgroundColor = NSColor.black.cgColor
        loupeLayer.addSublayer(loupeContent)

        loupeCrosshair.frame = loupeContent.frame
        loupeCrosshair.strokeColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        loupeCrosshair.lineWidth = 1
        loupeCrosshair.fillColor = nil
        loupeLayer.addSublayer(loupeCrosshair)

        styleText(loupeReadout, fontSize: 11)
        loupeReadout.alignmentMode = .center
        loupeReadout.frame = CGRect(x: 0, y: 0, width: Self.loupeSide, height: 20)
        loupeLayer.addSublayer(loupeReadout)

        root.addSublayer(loupeLayer)

        updateHintText()
        refresh()
    }

    private func styleText(_ text: CATextLayer, fontSize: CGFloat) {
        text.contentsScale = snapshot.scale
        text.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        text.fontSize = fontSize
        text.foregroundColor = NSColor.white.cgColor
        text.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        text.cornerRadius = 5
        text.alignmentMode = .center
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        positionHint()
        refresh()
    }

    private func updateHintText() {
        hintLayer.string = mode == .area
            ? String(localized: "Drag to select · Space to move · ⇧ square · ⌥ from center · Esc to cancel")
            : String(localized: "Click a window to capture it · Esc to cancel")
        positionHint()
    }

    private func positionHint() {
        let width: CGFloat = 620
        let height: CGFloat = 26
        hintLayer.frame = CGRect(x: (bounds.width - width) / 2,
                                 y: bounds.height - height - 40,
                                 width: width,
                                 height: height)
        // Vertically centre the single line of text inside the pill.
        hintLayer.frame = hintLayer.frame.insetBy(dx: 0, dy: 0)
        hintLayer.contentsScale = snapshot.scale
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .area ? .crosshair : .arrow)
    }

    // MARK: - Selection state

    /// Current selection in this view's coordinates, or `nil` when idle.
    var selectionRect: CGRect? {
        guard let anchorPoint, let currentPoint else { return nil }
        var rect = ScreenGeometry.rect(from: anchorPoint, to: currentPoint)

        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            let side = max(rect.width, rect.height)
            let signX: CGFloat = currentPoint.x >= anchorPoint.x ? 1 : -1
            let signY: CGFloat = currentPoint.y >= anchorPoint.y ? 1 : -1
            rect = ScreenGeometry.rect(from: anchorPoint,
                                       to: CGPoint(x: anchorPoint.x + side * signX,
                                                   y: anchorPoint.y + side * signY))
        }
        if flags.contains(.option) {
            rect = CGRect(x: anchorPoint.x - rect.width,
                          y: anchorPoint.y - rect.height,
                          width: rect.width * 2,
                          height: rect.height * 2)
        }
        return rect.intersection(bounds)
    }

    func reset() {
        anchorPoint = nil
        currentPoint = nil
        isMovingSelection = false
        hoveredCandidate = nil
        refresh()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard mode == .area else {
            handleWindowClick(at: point)
            return
        }
        anchorPoint = point
        currentPoint = point
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area else { return }
        let point = convert(event.locationInWindow, from: nil)
        if isMovingSelection, let moveOrigin, let movedRectAtStart {
            let delta = CGPoint(x: point.x - moveOrigin.x, y: point.y - moveOrigin.y)
            let moved = movedRectAtStart.offsetBy(dx: delta.x, dy: delta.y)
            anchorPoint = CGPoint(x: moved.minX, y: moved.minY)
            currentPoint = CGPoint(x: moved.maxX, y: moved.maxY)
        } else {
            currentPoint = point
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        let rect = selectionRect
        anchorPoint = nil
        currentPoint = nil
        isMovingSelection = false
        refresh()
        guard let rect, rect.width >= 2, rect.height >= 2 else {
            // A bare click is treated as "no selection", not a capture.
            return
        }
        controller?.viewDidSelectArea(rect, in: self)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mode == .window {
            let match = candidates.first { $0.appKitFrame.contains(globalPoint(from: point)) }
            if match?.scWindow.windowID != hoveredCandidate?.scWindow.windowID {
                hoveredCandidate = match
            }
        }
        refresh(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        loupeLayer.isHidden = true
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            controller?.cancel()
        case 49: // Space
            if anchorPoint != nil, !isMovingSelection, let rect = selectionRect {
                isMovingSelection = true
                movedRectAtStart = rect
                moveOrigin = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
            }
        case 36, 76: // Return / keypad enter confirms window selection
            if mode == .window, let hoveredCandidate {
                controller?.viewDidSelectWindow(hoveredCandidate)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isMovingSelection = false
            moveOrigin = nil
            movedRectAtStart = nil
        } else {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        refresh()
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    // MARK: - Window mode click

    func handleWindowClick(at point: CGPoint) {
        guard let candidate = candidates.first(where: { $0.appKitFrame.contains(globalPoint(from: point)) }) else {
            return
        }
        controller?.viewDidSelectWindow(candidate)
    }

    func globalPoint(from local: CGPoint) -> CGPoint {
        CGPoint(x: snapshot.frame.minX + local.x, y: snapshot.frame.minY + local.y)
    }

    func localPoint(fromGlobal global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - snapshot.frame.minX, y: global.y - snapshot.frame.minY)
    }

    // MARK: - Rendering

    func refresh(at cursor: CGPoint? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let highlight: CGRect?
        switch mode {
        case .area:
            highlight = selectionRect
        case .window:
            highlight = hoveredCandidate.map { localRect(fromGlobal: $0.appKitFrame).intersection(bounds) }
        }

        let path = CGMutablePath()
        path.addRect(bounds)
        if let highlight, highlight.width > 0, highlight.height > 0 {
            path.addRect(highlight)
        }
        dimLayer.path = path

        if let highlight, highlight.width > 0, highlight.height > 0 {
            borderLayer.path = CGPath(rect: highlight.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            updateInfoLayer(for: highlight)
        } else {
            borderLayer.path = nil
            infoLayer.isHidden = true
        }

        if mode == .area, let cursor {
            updateLoupe(at: cursor)
        } else if mode == .window {
            loupeLayer.isHidden = true
        }
    }

    private func localRect(fromGlobal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
    }

    private func updateInfoLayer(for rect: CGRect) {
        let widthPixels = Int((rect.width * snapshot.scale).rounded())
        let heightPixels = Int((rect.height * snapshot.scale).rounded())
        if mode == .window, let hoveredCandidate {
            infoLayer.string = "\(hoveredCandidate.applicationName) · \(widthPixels) × \(heightPixels) px"
        } else {
            infoLayer.string = "\(widthPixels) × \(heightPixels) px"
        }
        let text = (infoLayer.string as? String) ?? ""
        let width = max(96, CGFloat(text.count) * 7.4 + 18)
        let height: CGFloat = 22
        var origin = CGPoint(x: rect.midX - width / 2, y: rect.minY - height - 8)
        if origin.y < 6 { origin.y = min(rect.maxY + 8, bounds.height - height - 6) }
        origin.x = min(max(6, origin.x), bounds.width - width - 6)
        infoLayer.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
        infoLayer.isHidden = false
    }

    private func updateLoupe(at cursor: CGPoint) {
        let scale = snapshot.scale
        let source = Self.loupeSourcePixels
        let pixelX = cursor.x * scale
        let pixelYFromTop = (bounds.height - cursor.y) * scale
        var cropX = (pixelX - source / 2).rounded()
        var cropY = (pixelYFromTop - source / 2).rounded()
        cropX = min(max(0, cropX), max(0, CGFloat(snapshot.image.width) - source))
        cropY = min(max(0, cropY), max(0, CGFloat(snapshot.image.height) - source))
        let cropRect = CGRect(x: cropX, y: cropY, width: source, height: source)

        guard cropRect.maxX <= CGFloat(snapshot.image.width),
              cropRect.maxY <= CGFloat(snapshot.image.height),
              let cropped = snapshot.image.cropping(to: cropRect) else {
            loupeLayer.isHidden = true
            return
        }

        loupeContent.contents = cropped
        loupeReadout.string = "\(Int(pixelX))  \(Int(pixelYFromTop))"
        loupeReadout.contentsScale = scale

        // Centre crosshair sized to one source pixel.
        let cell = Self.loupeSide / source
        let crossPath = CGMutablePath()
        let mid = Self.loupeSide / 2
        crossPath.addRect(CGRect(x: mid - cell / 2, y: mid - cell / 2, width: cell, height: cell))
        loupeCrosshair.path = crossPath

        var origin = CGPoint(x: cursor.x + 24, y: cursor.y - loupeLayer.bounds.height - 24)
        if origin.x + loupeLayer.bounds.width > bounds.width - 8 {
            origin.x = cursor.x - loupeLayer.bounds.width - 24
        }
        if origin.y < 8 { origin.y = cursor.y + 24 }
        origin.y = min(origin.y, bounds.height - loupeLayer.bounds.height - 8)
        origin.x = max(8, origin.x)
        loupeLayer.frame = CGRect(origin: origin, size: loupeLayer.bounds.size)
        loupeLayer.isHidden = false
    }
}
