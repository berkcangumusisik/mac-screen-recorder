import AppKit
import CoreImage

/// Applies a `VideoEdit` to a single frame.
///
/// Overlays are drawn before the zoom transform so a redaction keeps covering
/// the same content even while the frame is being magnified.
final class VideoFrameRenderer {

    let sourceSize: CGSize
    let contentSize: CGSize
    let canvasSize: CGSize

    private let edit: VideoEdit
    private let layout: PresentationRenderer.Layout?
    private let plate: CIImage?
    private let contentMask: CIImage?
    private var textImages: [UUID: CIImage] = [:]

    init(edit: VideoEdit, sourceSize: CGSize) {
        self.edit = edit
        self.sourceSize = sourceSize
        self.contentSize = edit.outputSize(forSource: sourceSize)

        if let style = edit.style, let plate = PresentationRenderer.plate(contentSize: contentSize, style: style) {
            self.layout = plate.layout
            self.plate = CIImage(cgImage: plate.image)
            self.canvasSize = CGSize(width: CGFloat(plate.image.width), height: CGFloat(plate.image.height))
            self.contentMask = Self.roundedMask(size: plate.layout.contentRect.size,
                                                radius: CGFloat(style.cornerRadius))
                .map { CIImage(cgImage: $0) }
        } else {
            self.layout = nil
            self.plate = nil
            self.canvasSize = contentSize
            self.contentMask = nil
        }

        for overlay in edit.overlays where overlay.kind == .text {
            if let image = Self.textImage(for: overlay, sourceSize: sourceSize) {
                textImages[overlay.id] = CIImage(cgImage: image)
            }
        }
    }

    /// `time` is in source asset seconds.
    func render(_ input: CIImage, at time: Double) -> CIImage {
        var image = input
        let extent = image.extent
        if extent.origin != .zero {
            image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        }
        let size = CGSize(width: image.extent.width, height: image.extent.height)

        image = applyOverlays(to: image, size: size, time: time)
        image = applyZoom(to: image, size: size, time: time)

        // Scale the frame to the content size.
        if size.width != contentSize.width || size.height != contentSize.height {
            image = image.transformed(by: CGAffineTransform(scaleX: contentSize.width / size.width,
                                                             y: contentSize.height / size.height))
        }

        guard let plate, let layout else { return image }

        // Place the content inside the styled plate, with rounded corners.
        let contentRect = layout.contentRect
        let ciY = canvasSize.height - contentRect.maxY
        var placed = image.transformed(by: CGAffineTransform(translationX: contentRect.minX, y: ciY))
        if let contentMask {
            let mask = contentMask.transformed(by: CGAffineTransform(translationX: contentRect.minX, y: ciY))
            placed = placed.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: plate,
                kCIInputMaskImageKey: mask
            ])
            return placed.cropped(to: CGRect(origin: .zero, size: canvasSize))
        }
        return placed.composited(over: plate).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    // MARK: - Steps

    private func applyOverlays(to image: CIImage, size: CGSize, time: Double) -> CIImage {
        var result = image
        for overlay in edit.overlays where overlay.isVisible(at: time) {
            let rect = pixelRect(overlay.frame, in: size)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            switch overlay.kind {
            case .redaction:
                let block = CIImage(color: CIColor(cgColor: overlay.backgroundColor.cgColor))
                    .cropped(to: rect)
                result = block.composited(over: result)
            case .text:
                guard let text = textImages[overlay.id] else { continue }
                let placed = text.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
                result = placed.composited(over: result)
            }
        }
        return result
    }

    private func applyZoom(to image: CIImage, size: CGSize, time: Double) -> CIImage {
        guard let zoom = edit.zooms.first(where: { $0.intensity(at: time) > 0 }) else { return image }
        let transform = zoom.transform(at: time, videoSize: size, flipY: true)
        guard transform != .identity else { return image }
        return image.transformed(by: transform).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Normalised top-left rect -> Core Image pixel rect (bottom-left origin).
    private func pixelRect(_ normalised: CGRect, in size: CGSize) -> CGRect {
        let width = normalised.width * size.width
        let height = normalised.height * size.height
        let x = normalised.minX * size.width
        let y = size.height - (normalised.minY * size.height) - height
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    // MARK: - Cached images

    private static func textImage(for overlay: VideoOverlay, sourceSize: CGSize) -> CGImage? {
        let width = Int((overlay.frame.width * sourceSize.width).rounded())
        let height = Int((overlay.frame.height * sourceSize.height).rounded())
        guard width > 1, height > 1, !overlay.text.isEmpty,
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
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        overlay.backgroundColor.nsColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        let fontSize = max(9, overlay.fontFraction * sourceSize.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: overlay.color.nsColor,
            .paragraphStyle: paragraph
        ]
        let inset = rect.insetBy(dx: fontSize * 0.4, dy: fontSize * 0.25)
        (overlay.text as NSString).draw(in: inset, withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func roundedMask(size: CGSize, radius: CGFloat) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
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
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.white.cgColor)
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if radius > 0.5 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        } else {
            context.fill(rect)
        }
        return context.makeImage()
    }
}
