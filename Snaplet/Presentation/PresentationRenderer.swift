import AppKit

/// Turns a flat screenshot into a share-ready image: background, padding,
/// rounded corners, shadow, an optional neutral window frame and a caption.
///
/// The window frame is Snaplet's own design — a plain bar with three neutral
/// dots — and does not imitate any operating system or product.
enum PresentationRenderer {

    struct Layout: Equatable {
        var canvasSize: CGSize
        /// Frame (title bar + content) in top-left canvas coordinates.
        var frameRect: CGRect
        /// Content image inside the frame.
        var contentRect: CGRect
        var titleBarHeight: CGFloat
        var titleRect: CGRect?
        var subtitleRect: CGRect?
    }

    /// Pure layout maths, kept separate so it can be unit tested without pixels.
    static func layout(contentSize: CGSize, style: StylePreset) -> Layout {
        let longest = max(contentSize.width, contentSize.height)
        let padding = max(8, longest * style.paddingFraction)
        let titleBarHeight = style.showsWindowFrame ? max(26, contentSize.width * 0.035) : 0

        let titleFontSize = max(18, longest * 0.032)
        let subtitleFontSize = titleFontSize * 0.66
        let hasTitle = !style.title.isEmpty
        let hasSubtitle = !style.subtitle.isEmpty
        let captionHeight = (hasTitle ? titleFontSize * 1.45 : 0)
            + (hasSubtitle ? subtitleFontSize * 1.5 : 0)
            + ((hasTitle || hasSubtitle) ? padding * 0.5 : 0)

        let frameSize = CGSize(width: contentSize.width, height: contentSize.height + titleBarHeight)
        var canvasWidth = frameSize.width + padding * 2
        var canvasHeight = frameSize.height + padding * 2 + captionHeight

        if let ratio = style.aspect.ratio {
            let currentRatio = canvasWidth / canvasHeight
            if currentRatio < ratio {
                canvasWidth = canvasHeight * ratio
            } else if currentRatio > ratio {
                canvasHeight = canvasWidth / ratio
            }
        }

        let frameOriginX = (canvasWidth - frameSize.width) / 2
        let frameOriginY = (canvasHeight - frameSize.height - captionHeight) / 2 + captionHeight
        let frameRect = CGRect(origin: CGPoint(x: frameOriginX, y: frameOriginY), size: frameSize)
        let contentRect = CGRect(x: frameRect.minX,
                                 y: frameRect.minY + titleBarHeight,
                                 width: contentSize.width,
                                 height: contentSize.height)

        var titleRect: CGRect?
        var subtitleRect: CGRect?
        var cursorY = frameRect.minY - captionHeight + padding * 0.25
        if hasTitle {
            titleRect = CGRect(x: padding, y: cursorY, width: canvasWidth - padding * 2, height: titleFontSize * 1.35)
            cursorY += titleFontSize * 1.45
        }
        if hasSubtitle {
            subtitleRect = CGRect(x: padding, y: cursorY, width: canvasWidth - padding * 2, height: subtitleFontSize * 1.4)
        }

        return Layout(canvasSize: CGSize(width: canvasWidth.rounded(), height: canvasHeight.rounded()),
                      frameRect: frameRect,
                      contentRect: contentRect,
                      titleBarHeight: titleBarHeight,
                      titleRect: titleRect,
                      subtitleRect: subtitleRect)
    }

    static func render(content: CGImage, style: StylePreset, maxLongestEdge: CGFloat? = nil) -> CGImage? {
        let contentSize = CGSize(width: content.width, height: content.height)
        let layout = layout(contentSize: contentSize, style: style)
        guard let image = draw(content: content, style: style, layout: layout) else { return nil }

        guard let maxLongestEdge else { return image }
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxLongestEdge else { return image }
        let factor = maxLongestEdge / longest
        return ImageExporter.resized(image,
                                     to: CGSize(width: CGFloat(image.width) * factor,
                                                height: CGFloat(image.height) * factor))
    }

    private static func draw(content: CGImage, style: StylePreset, layout: Layout) -> CGImage? {
        let width = Int(layout.canvasSize.width)
        let height = Int(layout.canvasSize.height)
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
        drawBackground(style.background, in: context, size: layout.canvasSize)

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let radius = CGFloat(style.cornerRadius)
        let framePath = NSBezierPath(roundedRect: layout.frameRect, xRadius: radius, yRadius: radius)

        if style.shadow.opacity > 0 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = CGFloat(style.shadow.radius)
            shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(style.shadow.offsetY))
            shadow.shadowColor = NSColor.black.withAlphaComponent(CGFloat(style.shadow.opacity))
            shadow.set()
            NSColor.black.setFill()
            framePath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        framePath.addClip()
        if style.showsWindowFrame {
            drawWindowChrome(style: style, layout: layout)
        }
        NSImage(cgImage: content, size: layout.contentRect.size).draw(in: layout.contentRect)
        NSGraphicsContext.restoreGraphicsState()

        drawCaption(style: style, layout: layout)

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func drawBackground(_ background: BackgroundStyle, in context: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        switch background {
        case .transparent:
            context.clear(rect)
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let start, let end, let angle):
            let colors = [start.cgColor, end.cgColor] as CFArray
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            let radians = angle * .pi / 180
            let dx = cos(radians) * size.width / 2
            let dy = sin(radians) * size.height / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: center.x - dx, y: center.y - dy),
                                       end: CGPoint(x: center.x + dx, y: center.y + dy),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .image(let path):
            guard let image = NSImage(contentsOfFile: path) else {
                context.setFillColor(RGBAColor(red: 0.15, green: 0.15, blue: 0.18).cgColor)
                context.fill(rect)
                return
            }
            // Aspect-fill so a background photo never letterboxes.
            let imageSize = image.size
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            image.draw(in: CGRect(origin: origin, size: drawSize))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Snaplet's own neutral frame: a plain bar with three muted dots.
    private static func drawWindowChrome(style: StylePreset, layout: Layout) {
        let bar = CGRect(x: layout.frameRect.minX,
                         y: layout.frameRect.minY,
                         width: layout.frameRect.width,
                         height: layout.titleBarHeight)
        let isDark = style.textColor.red > 0.5
        (isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(rect: bar).fill()

        let dotDiameter = min(bar.height * 0.34, 14)
        let spacing = dotDiameter * 1.7
        var x = bar.minX + spacing * 0.8
        let y = bar.midY - dotDiameter / 2
        let dotColor = isDark ? NSColor(white: 0.42, alpha: 1) : NSColor(white: 0.72, alpha: 1)
        dotColor.setFill()
        for _ in 0..<3 {
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: dotDiameter, height: dotDiameter)).fill()
            x += spacing
        }
    }

    private static func drawCaption(style: StylePreset, layout: Layout) {
        if let titleRect = layout.titleRect {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: titleRect.height / 1.35, weight: .bold),
                .foregroundColor: style.textColor.nsColor
            ]
            (style.title as NSString).draw(in: titleRect, withAttributes: attributes)
        }
        if let subtitleRect = layout.subtitleRect {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: subtitleRect.height / 1.4, weight: .regular),
                .foregroundColor: style.textColor.nsColor.withAlphaComponent(0.82)
            ]
            (style.subtitle as NSString).draw(in: subtitleRect, withAttributes: attributes)
        }
    }
}
