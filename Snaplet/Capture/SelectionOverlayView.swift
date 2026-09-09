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
    private let infoLabel: PillLabel
    private let hintLabel: PillLabel
    private let loupeLayer = CALayer()
    private let loupeContent = CALayer()
    private let loupeCrosshair = CAShapeLayer()
    private let loupeReadout: PillLabel

    private var hoveredCandidate: WindowCandidate?
    private var trackingArea: NSTrackingArea?
    /// Colour under the pointer, kept current so pressing C can copy it.
    private var colorUnderPointer: NSColor?

    private static let loupeSide: CGFloat = 152
    private static let loupeSourcePixels: CGFloat = 30

    init(snapshot: DisplaySnapshot, mode: SelectionOverlayController.Mode) {
        self.snapshot = snapshot
        self.mode = mode
        infoLabel = PillLabel(fontSize: 12, contentsScale: snapshot.scale)
        hintLabel = PillLabel(fontSize: 12, contentsScale: snapshot.scale)
        loupeReadout = PillLabel(fontSize: 11, contentsScale: snapshot.scale)
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

        infoLabel.isHidden = true
        root.addSublayer(infoLabel.container)
        root.addSublayer(hintLabel.container)

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

        loupeReadout.frame = CGRect(x: 0, y: 0, width: Self.loupeSide, height: 20)
        loupeLayer.addSublayer(loupeReadout.container)

        root.addSublayer(loupeLayer)

        updateHintText()
        refresh()
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
        hintLabel.string = mode == .area
            ? String(localized: "Drag to select · Space to move · ⇧ square · ⌥ from center · C copies the colour · Esc to cancel")
            : String(localized: "Click a window to capture it · Esc to cancel")
        positionHint()
    }

    private func positionHint() {
        let text = (hintLabel.string ?? "")
        let height: CGFloat = 28
        let width = min(bounds.width - 48, hintLabel.preferredWidth(for: text))
        hintLabel.frame = CGRect(x: ((bounds.width - width) / 2).rounded(),
                                 y: bounds.height - height - 40,
                                 width: width,
                                 height: height)
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

    /// The part of the global selection that falls on this display, in local
    /// coordinates. The selection itself lives on the controller so it can cross
    /// displays.
    var selectionRect: CGRect? {
        guard let global = controller?.globalSelection else { return nil }
        let local = localRect(fromGlobal: global)
        let clipped = local.intersection(bounds)
        return clipped.isNull ? nil : clipped
    }

    func reset() {
        hoveredCandidate = nil
        refresh()
    }

    /// Called by the controller when the shared drag changes.
    func refreshFromController() {
        refresh(at: window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) })
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard mode == .area else {
            handleWindowClick(at: point)
            return
        }
        controller?.beginDrag(at: globalPoint(from: point))
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area else { return }
        // Dragging past this display's edge keeps arriving here, which is how
        // the selection is allowed to continue onto the next monitor.
        controller?.updateDrag(to: globalPoint(from: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area else { return }
        controller?.updateDrag(to: globalPoint(from: convert(event.locationInWindow, from: nil)))
        controller?.endDrag()
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
        case 8: // C copies the colour under the pointer, the way a picker should
            if mode == .area, let colorUnderPointer {
                Clipboard.copy(text: ColorFormatting.hex(colorUnderPointer))
                controller?.cancel()
            }
        case 49: // Space
            if let window {
                let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                controller?.beginMovingSelection(from: globalPoint(from: local))
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
            controller?.endMovingSelection()
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
            updateInfoLabel(for: highlight)
        } else {
            borderLayer.path = nil
            infoLabel.isHidden = true
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

    private func updateInfoLabel(for rect: CGRect) {
        let widthPixels = Int((rect.width * snapshot.scale).rounded())
        let heightPixels = Int((rect.height * snapshot.scale).rounded())
        let text: String
        if mode == .window, let hoveredCandidate {
            text = "\(hoveredCandidate.applicationName) · \(widthPixels) × \(heightPixels) px"
        } else {
            text = "\(widthPixels) × \(heightPixels) px"
        }
        infoLabel.string = text

        let width = max(96, infoLabel.preferredWidth(for: text, horizontalPadding: 10))
        let height: CGFloat = 24
        var origin = CGPoint(x: rect.midX - width / 2, y: rect.minY - height - 8)
        if origin.y < 6 { origin.y = min(rect.maxY + 8, bounds.height - height - 6) }
        origin.x = min(max(6, origin.x), bounds.width - width - 6)
        infoLabel.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
        infoLabel.isHidden = false
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
        let color = Self.color(in: snapshot.image, atX: Int(pixelX), y: Int(pixelYFromTop))
        colorUnderPointer = color
        if let color {
            loupeReadout.string = ColorFormatting.hex(color)
        } else {
            loupeReadout.string = "\(Int(pixelX))  \(Int(pixelYFromTop))"
        }

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

extension SelectionOverlayView {
    /// Reads one pixel out of the display snapshot. Drawing a single pixel into
    /// a one-by-one context is cheap enough to do on every mouse move, and it
    /// avoids keeping a full uncompressed copy of a 5K display in memory.
    static func color(in image: CGImage, atX x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: 1,
                                          height: 1,
                                          bitsPerComponent: 8,
                                          bytesPerRow: 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255,
                       green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255,
                       alpha: 1)
    }
}

/// Colour values in the form people paste into code.
enum ColorFormatting {
    static func hex(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

/// A rounded pill with a single centred line of text.
///
/// `CATextLayer` draws its string flush with the top of its own bounds, so the
/// text needs its own layer inset inside the background to look centred.
final class PillLabel {
    let container = CALayer()
    private let textLayer = CATextLayer()
    private let fontSize: CGFloat

    init(fontSize: CGFloat, contentsScale: CGFloat) {
        self.fontSize = fontSize
        container.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        container.cornerRadius = 6
        container.contentsScale = contentsScale

        textLayer.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .middle
        textLayer.contentsScale = contentsScale
        container.addSublayer(textLayer)
    }

    var string: String? {
        get { textLayer.string as? String }
        set { textLayer.string = newValue }
    }

    var isHidden: Bool {
        get { container.isHidden }
        set { container.isHidden = newValue }
    }

    var frame: CGRect {
        get { container.frame }
        set {
            container.frame = newValue
            let lineHeight = (fontSize * 1.22).rounded()
            textLayer.frame = CGRect(x: 0,
                                     y: ((newValue.height - lineHeight) / 2).rounded(),
                                     width: newValue.width,
                                     height: lineHeight)
        }
    }

    /// Width this pill needs for `text`, measured with the font it actually
    /// draws in. Guessing from character count silently truncates as soon as a
    /// translation is longer or the font changes.
    func preferredWidth(for text: String, horizontalPadding: CGFloat = 20) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(measured) + horizontalPadding * 2
    }
}
