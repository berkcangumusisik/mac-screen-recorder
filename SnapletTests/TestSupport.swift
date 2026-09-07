import AppKit
import XCTest
@testable import Snaplet

enum TestImages {

    /// Solid-colour image, useful as a predictable canvas.
    static func solid(width: Int, height: Int, color: NSColor = .white) -> CGImage {
        make(width: width, height: height) { context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Left half white, right half black — enough structure to notice a flip or
    /// an unexpected rotation.
    static func split(width: Int, height: Int) -> CGImage {
        make(width: width, height: height) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    /// Fine vertical stripes: any averaging filter changes these pixels.
    static func stripes(width: Int, height: Int, barWidth: Int = 2) -> CGImage {
        make(width: width, height: height) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.black.cgColor)
            var x = 0
            while x < width {
                context.fill(CGRect(x: x, y: 0, width: barWidth, height: height))
                x += barWidth * 2
            }
        }
    }

    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }
}

struct PixelSampler {
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        let stride = imageWidth * 4
        var buffer = [UInt8](repeating: 0, count: stride * imageHeight)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress,
                                    width: imageWidth,
                                    height: imageHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: stride,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        }
        width = imageWidth
        height = imageHeight
        bytesPerRow = stride
        data = buffer
    }

    /// `x` and `y` use image pixel coordinates with a top-left origin.
    func rgba(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let flippedY = y
        let offset = flippedY * bytesPerRow + x * 4
        guard offset + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]), Int(data[offset + 3]))
    }

    func isApproximately(_ expected: (Int, Int, Int), atX x: Int, y: Int, tolerance: Int = 12) -> Bool {
        let pixel = rgba(x: x, y: y)
        return abs(pixel.r - expected.0) <= tolerance
            && abs(pixel.g - expected.1) <= tolerance
            && abs(pixel.b - expected.2) <= tolerance
    }
}
