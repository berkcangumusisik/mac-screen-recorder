import AppKit
import CoreGraphics

/// Snaplet deals with three coordinate spaces and converts between them in
/// exactly one place, here:
///
/// 1. **AppKit points** — origin at the bottom-left of the primary display, y up.
///    Used by `NSScreen`, `NSWindow` and mouse events.
/// 2. **CoreGraphics / display points** — origin at the top-left of the primary
///    display, y down. Used by `CGDisplayBounds`, `SCDisplay.frame` and
///    `SCStreamConfiguration.sourceRect`.
/// 3. **Image pixels** — origin at the top-left of a captured image, y down,
///    scaled by the display's backing scale factor.
///
/// The vertical flip constant is the primary display's height, because the
/// primary display is the one whose AppKit origin is `(0, 0)`.
struct ScreenGeometry: Equatable {
    /// Height of the primary display in AppKit points.
    let primaryHeight: CGFloat

    init(primaryHeight: CGFloat) {
        self.primaryHeight = primaryHeight
    }

    @MainActor
    static var current: ScreenGeometry {
        ScreenGeometry(primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    // MARK: - AppKit <-> CoreGraphics

    func flip(_ y: CGFloat) -> CGFloat { primaryHeight - y }

    func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: flip(point.y))
    }

    func appKitPoint(fromCG point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: flip(point.y))
    }

    /// The conversion is an involution: applying it twice returns the input.
    func cgRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: flip(rect.maxY), width: rect.width, height: rect.height)
    }

    func appKitRect(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: flip(rect.maxY), width: rect.width, height: rect.height)
    }

    // MARK: - Points -> pixels

    /// Converts a rect expressed in AppKit points into pixel coordinates inside
    /// an image captured from `displayFrame` (also AppKit points) at `scale`.
    ///
    /// Edges are rounded independently and then clamped to the image so a
    /// selection never produces a half-pixel or out-of-bounds crop.
    static func pixelCropRect(selection: CGRect,
                              inDisplayFrame displayFrame: CGRect,
                              scale: CGFloat,
                              imagePixelSize: CGSize) -> CGRect? {
        guard scale > 0, imagePixelSize.width >= 1, imagePixelSize.height >= 1 else { return nil }

        // Move into display-local coordinates, flipping y inside the display.
        let localMinX = selection.minX - displayFrame.minX
        let localMaxX = selection.maxX - displayFrame.minX
        let localMinY = displayFrame.maxY - selection.maxY
        let localMaxY = displayFrame.maxY - selection.minY

        var left = (localMinX * scale).rounded()
        var top = (localMinY * scale).rounded()
        var right = (localMaxX * scale).rounded()
        var bottom = (localMaxY * scale).rounded()

        left = max(0, min(left, imagePixelSize.width))
        right = max(0, min(right, imagePixelSize.width))
        top = max(0, min(top, imagePixelSize.height))
        bottom = max(0, min(bottom, imagePixelSize.height))

        let width = right - left
        let height = bottom - top
        guard width >= 1, height >= 1 else { return nil }
        return CGRect(x: left, y: top, width: width, height: height)
    }

    /// Normalises a drag between two points into a positive-size rect.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(a.x - b.x),
               height: abs(a.y - b.y))
    }
}
