import AppKit
import CoreImage
import CoreVideo

/// Draws the webcam overlay into each recorded frame.
///
/// The overlay is composited into the pixels that go to the encoder — it is not
/// merely a window on screen — so the exported file always contains it.
final class FrameCompositor {

    private let context: CIContext
    private let outputSize: CGSize
    private let overlayRect: CGRect
    private let mask: CIImage?

    init(outputSize: CGSize, overlay: WebcamOverlayConfiguration?) {
        self.outputSize = outputSize
        self.context = CIContext(options: [.cacheIntermediates: false])
        if let overlay {
            let rect = overlay.frame(inVideoSize: outputSize)
            overlayRect = rect
            mask = Self.makeMask(size: rect.size, shape: overlay.shape).map { CIImage(cgImage: $0) }
        } else {
            overlayRect = .zero
            mask = nil
        }
    }

    /// Renders `screen` (plus the webcam frame if there is one) into `destination`.
    func composite(screen: CVPixelBuffer, camera: CVPixelBuffer?, into destination: CVPixelBuffer) {
        var image = CIImage(cvPixelBuffer: screen)
        let screenExtent = image.extent
        if screenExtent.width != outputSize.width || screenExtent.height != outputSize.height {
            image = image.transformed(by: CGAffineTransform(scaleX: outputSize.width / screenExtent.width,
                                                            y: outputSize.height / screenExtent.height))
        }

        if let camera, let mask {
            var cameraImage = CIImage(cvPixelBuffer: camera)
            let extent = cameraImage.extent
            // Aspect-fill the overlay rectangle, then crop to it.
            let scale = max(overlayRect.width / extent.width, overlayRect.height / extent.height)
            cameraImage = cameraImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let scaled = cameraImage.extent

            // CoreImage is y-up; the overlay rect is expressed top-left.
            let targetY = outputSize.height - overlayRect.maxY
            let offsetX = overlayRect.minX - scaled.minX - (scaled.width - overlayRect.width) / 2
            let offsetY = targetY - scaled.minY - (scaled.height - overlayRect.height) / 2
            cameraImage = cameraImage
                .transformed(by: CGAffineTransform(translationX: offsetX.rounded(), y: offsetY.rounded()))
                .cropped(to: CGRect(x: overlayRect.minX, y: targetY,
                                    width: overlayRect.width, height: overlayRect.height))

            let placedMask = mask.transformed(by: CGAffineTransform(translationX: overlayRect.minX,
                                                                    y: targetY))
            image = cameraImage.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: placedMask
            ])
        }

        context.render(image, to: destination)
    }

    /// White shape on transparent, used as the overlay's alpha mask.
    private static func makeMask(size: CGSize, shape: WebcamShape) -> CGImage? {
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
        switch shape {
        case .circle:
            context.fillEllipse(in: rect)
        case .roundedRectangle:
            let radius = min(size.width, size.height) * 0.18
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            context.addPath(path)
            context.fillPath()
        }
        return context.makeImage()
    }
}
