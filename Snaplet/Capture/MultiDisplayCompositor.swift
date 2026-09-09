import AppKit
import CoreGraphics

/// Builds one image from a selection that crosses more than one display.
///
/// Displays can differ in backing scale, so the result is rendered at the
/// highest scale involved: downscaling a Retina region to match a 1× monitor
/// would throw away detail the user can see. Any part of the selection that no
/// display covers — the gap between two monitors of different heights, say —
/// stays transparent rather than being filled with invented pixels.
enum MultiDisplayCompositor {

    struct Result {
        let image: CGImage
        /// Pixels per point of the composed image.
        let scale: CGFloat
    }

    /// `selection` is in global AppKit points.
    static func composite(selection: CGRect, from snapshots: [DisplaySnapshot]) -> Result? {
        let covering = snapshots.filter { $0.frame.intersects(selection) }
        guard !covering.isEmpty, selection.width >= 1, selection.height >= 1 else { return nil }

        // A selection inside a single display needs no compositing.
        if covering.count == 1, let only = covering.first {
            guard let cropRect = ScreenGeometry.pixelCropRect(selection: selection,
                                                              inDisplayFrame: only.frame,
                                                              scale: only.scale,
                                                              imagePixelSize: only.pixelSize),
                  let cropped = only.image.cropping(to: cropRect) else { return nil }
            return Result(image: cropped, scale: only.scale)
        }

        let scale = covering.map(\.scale).max() ?? 2
        let width = Int((selection.width * scale).rounded())
        let height = Int((selection.height * scale).rounded())
        guard width >= 1, height >= 1,
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

        for snapshot in covering {
            let piece = snapshot.frame.intersection(selection)
            guard piece.width >= 0.5, piece.height >= 0.5 else { continue }
            guard let cropRect = ScreenGeometry.pixelCropRect(selection: piece,
                                                              inDisplayFrame: snapshot.frame,
                                                              scale: snapshot.scale,
                                                              imagePixelSize: snapshot.pixelSize),
                  let cropped = snapshot.image.cropping(to: cropRect) else { continue }

            // Place it in the output. The context is y-up, and so is AppKit, so
            // the vertical offset is measured from the bottom of the selection.
            let destination = CGRect(x: (piece.minX - selection.minX) * scale,
                                     y: (piece.minY - selection.minY) * scale,
                                     width: piece.width * scale,
                                     height: piece.height * scale)
            context.draw(cropped, in: destination)
        }

        guard let image = context.makeImage() else { return nil }
        return Result(image: image, scale: scale)
    }

    /// Whether a selection touches more than one display.
    static func spansMultipleDisplays(_ selection: CGRect, snapshots: [DisplaySnapshot]) -> Bool {
        snapshots.filter { $0.frame.intersects(selection) }.count > 1
    }
}
