import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Rasterises a `RenderRequest`.
///
/// The preview and the exported file both go through here, so what the user
/// sees is exactly what is written to disk. Because the result is a fresh
/// bitmap, obscured regions cannot be recovered from the output: the source
/// pixels are never copied into the exported file.
enum AnnotationRenderer {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// The annotated image, without presentation styling.
    static func renderFlat(_ request: RenderRequest) -> CGImage? {
        let outputSize = request.croppedPixelSize
        let width = Int(outputSize.width.rounded())
        let height = Int(outputSize.height.rounded())
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.interpolationQuality = .high

        // 1. Base image: crop, then rotate, drawn in the default y-up space.
        if let cropped = request.source.cropping(to: request.cropRect.integral),
           let rotated = rotate(cropped, quarterTurns: request.quarterTurns) {
            context.draw(rotated, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }

        // 2. Flip into a top-left origin space and apply the crop/rotation
        //    transform so annotations can stay in source coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.concatenate(request.sourceToOutput)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        drawAnnotations(request.annotations, source: request.source)
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }

    /// The final image, including any presentation styling.
    static func render(_ request: RenderRequest) -> CGImage? {
        guard let flat = renderFlat(request) else { return nil }
        guard let style = request.style else { return flat }
        return PresentationRenderer.render(content: flat, style: style)
    }

    // MARK: - Rotation

    static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }

        let width = turns % 2 == 0 ? image.width : image.height
        let height = turns % 2 == 0 ? image.height : image.width
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // Positive CoreGraphics rotation is counter-clockwise; quarter turns
        // are defined clockwise, matching the rotate button in the editor.
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.draw(image,
                     in: CGRect(x: -CGFloat(image.width) / 2,
                                y: -CGFloat(image.height) / 2,
                                width: CGFloat(image.width),
                                height: CGFloat(image.height)))
        return context.makeImage()
    }

    // MARK: - Annotation drawing

    /// Draws annotations into the current `NSGraphicsContext`, which must
    /// already be flipped and transformed into source pixel space. The editor
    /// canvas calls this too, so the preview cannot drift from the export.
    static func drawAnnotations(_ annotations: [Annotation], source: CGImage) {
        for annotation in annotations {
            draw(annotation, source: source)
        }
    }

    private static func draw(_ annotation: Annotation, source: CGImage) {
        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: annotation.frame)
            stroke(path, annotation)
        case .ellipse:
            let path = NSBezierPath(ovalIn: annotation.frame)
            stroke(path, annotation)
        case .line:
            let path = NSBezierPath()
            path.move(to: annotation.startPoint)
            path.line(to: annotation.endPoint)
            stroke(path, annotation)
        case .arrow:
            drawArrow(annotation)
        case .freehand:
            strokePolyline(annotation, alpha: 1, capRound: true)
        case .highlighter:
            strokePolyline(annotation, alpha: 0.35, capRound: false)
        case .text:
            drawText(annotation)
        case .callout:
            drawCallout(annotation)
        case .step:
            drawStep(annotation)
        case .blur, .pixelate:
            drawEffect(annotation, source: source)
        case .redaction:
            annotation.strokeColor.nsColor.setFill()
            NSBezierPath(rect: annotation.frame).fill()
        case .magnifier:
            drawMagnifier(annotation, source: source)
        }
    }

    private static func stroke(_ path: NSBezierPath, _ annotation: Annotation) {
        if let fill = annotation.fillColor, fill.alpha > 0 {
            fill.nsColor.setFill()
            path.fill()
        }
        path.lineWidth = annotation.lineWidth
        annotation.strokeColor.nsColor.setStroke()
        path.stroke()
    }

    private static func strokePolyline(_ annotation: Annotation, alpha: Double, capRound: Bool) {
        guard annotation.points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: annotation.points[0])
        for point in annotation.points.dropFirst() { path.line(to: point) }
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = capRound ? .round : .square
        path.lineJoinStyle = .round
        annotation.strokeColor.nsColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private static func drawArrow(_ annotation: Annotation) {
        let start = annotation.startPoint
        let end = annotation.endPoint
        // Annotation stores line width as Double for Codable stability, but every
        // point below is CGFloat. Converting once here keeps the arithmetic in a
        // single type: mixing the two leaves `cos` ambiguous on Xcode 16.
        let width = CGFloat(max(2, annotation.lineWidth))
        let headLength = max(width * 3.2, 12)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 1 else { return }

        let shaftEnd = CGPoint(x: end.x - cos(angle) * min(headLength * 0.85, length),
                               y: end.y - sin(angle) * min(headLength * 0.85, length))
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        annotation.strokeColor.nsColor.setStroke()
        shaft.stroke()

        let head = NSBezierPath()
        let spread = CGFloat.pi / 7
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - cos(angle - spread) * headLength,
                              y: end.y - sin(angle - spread) * headLength))
        head.line(to: CGPoint(x: end.x - cos(angle + spread) * headLength,
                              y: end.y - sin(angle + spread) * headLength))
        head.close()
        annotation.strokeColor.nsColor.setFill()
        head.fill()
    }

    private static func attributes(_ annotation: Annotation) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: annotation.strokeColor.nsColor
        ]
    }

    private static func drawText(_ annotation: Annotation) {
        guard !annotation.text.isEmpty else { return }
        if let fill = annotation.fillColor, fill.alpha > 0 {
            fill.nsColor.setFill()
            NSBezierPath(roundedRect: annotation.frame.insetBy(dx: -6, dy: -4),
                         xRadius: 6, yRadius: 6).fill()
        }
        (annotation.text as NSString).draw(in: annotation.frame, withAttributes: attributes(annotation))
    }

    private static func drawCallout(_ annotation: Annotation) {
        let bubble = annotation.frame
        let radius = min(14, min(bubble.width, bubble.height) / 3)
        let path = NSBezierPath(roundedRect: bubble, xRadius: radius, yRadius: radius)

        if let tail = annotation.points.first {
            let tailPath = NSBezierPath()
            let anchor = CGPoint(x: bubble.midX, y: tail.y > bubble.midY ? bubble.maxY : bubble.minY)
            let spread = min(bubble.width / 4, 22)
            tailPath.move(to: CGPoint(x: anchor.x - spread, y: anchor.y))
            tailPath.line(to: tail)
            tailPath.line(to: CGPoint(x: anchor.x + spread, y: anchor.y))
            tailPath.close()
            path.append(tailPath)
        }

        (annotation.fillColor ?? RGBAColor.white).nsColor.setFill()
        path.fill()
        annotation.strokeColor.nsColor.setStroke()
        path.lineWidth = max(1, annotation.lineWidth * 0.5)
        path.stroke()

        guard !annotation.text.isEmpty else { return }
        var textAttributes = attributes(annotation)
        textAttributes[.foregroundColor] = NSColor.black
        let inset = bubble.insetBy(dx: 10, dy: 8)
        (annotation.text as NSString).draw(in: inset, withAttributes: textAttributes)
    }

    private static func drawStep(_ annotation: Annotation) {
        let diameter = max(annotation.frame.width, 20)
        let circle = CGRect(x: annotation.frame.minX,
                            y: annotation.frame.minY,
                            width: diameter,
                            height: diameter)
        annotation.strokeColor.nsColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        ring.stroke()

        let label = "\(annotation.number)" as NSString
        let font = NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(at: CGPoint(x: circle.midX - size.width / 2,
                               y: circle.midY - size.height / 2),
                   withAttributes: attributes)
    }

    private static func drawEffect(_ annotation: Annotation, source: CGImage) {
        let region = annotation.frame.integral.intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard region.width >= 2, region.height >= 2,
              let cropped = source.cropping(to: region) else { return }

        let input = CIImage(cgImage: cropped)
        let output: CIImage?
        if annotation.kind == .blur {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(max(2, annotation.effectStrength))
            output = filter.outputImage?.cropped(to: input.extent)
        } else {
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(max(2, annotation.effectStrength))
            filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
            output = filter.outputImage?.cropped(to: input.extent)
        }

        guard let output,
              let rendered = ciContext.createCGImage(output, from: input.extent) else { return }
        NSImage(cgImage: rendered, size: region.size).draw(in: region)
    }

    private static func drawMagnifier(_ annotation: Annotation, source: CGImage) {
        let region = annotation.frame.integral.intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard region.width >= 2, region.height >= 2,
              let cropped = source.cropping(to: region) else { return }

        let zoom = max(1.2, annotation.zoom)
        let destination = CGRect(x: region.midX - region.width * zoom / 2,
                                 y: region.midY - region.height * zoom / 2,
                                 width: region.width * zoom,
                                 height: region.height * zoom)
        let radius = min(destination.width, destination.height) / 2
        let clip = NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSImage(cgImage: cropped, size: destination.size).draw(in: destination)
        NSGraphicsContext.restoreGraphicsState()

        annotation.strokeColor.nsColor.setStroke()
        clip.lineWidth = max(2, annotation.lineWidth)
        clip.stroke()
    }
}
