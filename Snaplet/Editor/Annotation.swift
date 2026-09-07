import CoreGraphics
import Foundation

/// One editing operation. Annotations are values stored in **source image pixel
/// coordinates** (top-left origin) and are never baked into the source image —
/// cropping, rotating and reordering all stay reversible until export.
struct Annotation: Identifiable, Equatable, Codable, Sendable {

    enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow
        case line
        case rectangle
        case ellipse
        case freehand
        case highlighter
        case text
        case callout
        case step
        case magnifier
        case blur
        case pixelate
        case redaction

        /// Tools whose geometry is a free-form path rather than a rectangle.
        var isPathBased: Bool { self == .freehand || self == .highlighter }

        /// Tools that obscure content. Only `redaction` is safe to describe as
        /// removal; the other two are visual effects.
        var obscuresContent: Bool { self == .blur || self == .pixelate || self == .redaction }
    }

    var id: UUID = UUID()
    var kind: Kind
    /// Bounding box in source pixel coordinates. For `line`/`arrow` the box is
    /// interpreted as start = one corner, end = the opposite corner, using
    /// `isFlippedHorizontally` / `isFlippedVertically` to recover direction.
    var frame: CGRect
    var strokeColor: RGBAColor = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    var fillColor: RGBAColor?
    var lineWidth: Double = 4
    var fontSize: Double = 28
    var text: String = ""
    /// Freehand and highlighter points, in source pixel coordinates.
    var points: [CGPoint] = []
    /// Step-marker number, assigned automatically and renumbered on delete.
    var number: Int = 1
    /// Magnifier zoom factor.
    var zoom: Double = 2
    /// Pixelate block size / blur radius in source pixels.
    var effectStrength: Double = 18
    var isFlippedHorizontally = false
    var isFlippedVertically = false

    var startPoint: CGPoint {
        CGPoint(x: isFlippedHorizontally ? frame.maxX : frame.minX,
                y: isFlippedVertically ? frame.maxY : frame.minY)
    }

    var endPoint: CGPoint {
        CGPoint(x: isFlippedHorizontally ? frame.minX : frame.maxX,
                y: isFlippedVertically ? frame.minY : frame.maxY)
    }

    /// Builds a line-like annotation from two arbitrary points.
    static func line(kind: Kind, from start: CGPoint, to end: CGPoint) -> Annotation {
        var annotation = Annotation(kind: kind,
                                    frame: CGRect(x: min(start.x, end.x),
                                                  y: min(start.y, end.y),
                                                  width: abs(end.x - start.x),
                                                  height: abs(end.y - start.y)))
        annotation.isFlippedHorizontally = end.x < start.x
        annotation.isFlippedVertically = end.y < start.y
        return annotation
    }

    /// Hit area used for selection, generous enough for thin strokes.
    func hitRect(padding: CGFloat) -> CGRect {
        frame.insetBy(dx: -padding, dy: -padding)
    }
}

/// Immutable description of everything needed to produce a final image.
/// Preview and export use the same struct, which is what keeps them identical.
struct RenderRequest: Sendable {
    let source: CGImage
    /// Crop in source pixel coordinates.
    let cropRect: CGRect
    /// 0–3 clockwise quarter turns applied after cropping.
    let quarterTurns: Int
    let annotations: [Annotation]
    let style: StylePreset?
    /// Pixels per point of the source image, used to size presentation chrome.
    let scale: CGFloat

    var croppedPixelSize: CGSize {
        let size = CGSize(width: cropRect.width, height: cropRect.height)
        return quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    /// Maps source pixel coordinates into the cropped-and-rotated output space.
    var sourceToOutput: CGAffineTransform {
        let translation = CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY)
        let width = cropRect.width
        let height = cropRect.height
        let rotation: CGAffineTransform
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        case 2: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 3: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        default: rotation = .identity
        }
        return translation.concatenating(rotation)
    }
}
