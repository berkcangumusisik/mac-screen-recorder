import AVFoundation
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

/// Writes a short, solid-colour H.264 file so tests can exercise the real
/// composition and export paths instead of mocking them.
enum TestVideo {

    static func make(url: URL,
                     size: CGSize = CGSize(width: 320, height: 240),
                     seconds: Double = 2,
                     frameRate: Int = 10,
                     color: NSColor = .red) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
                                                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                            kCVPixelBufferWidthKey as String: Int(size.width),
                                                            kCVPixelBufferHeightKey as String: Int(size.height)
                                                           ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let total = Int(seconds * Double(frameRate))
        for index in 0..<total {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { break }
            fill(pixelBuffer, with: color)
            adaptor.append(pixelBuffer,
                           withPresentationTime: CMTime(value: CMTimeValue(index),
                                                        timescale: CMTimeScale(frameRate)))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    private static func fill(_ pixelBuffer: CVPixelBuffer, with color: NSColor) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let converted = color.usingColorSpace(.sRGB) ?? .red
        let blue = UInt8(converted.blueComponent * 255)
        let green = UInt8(converted.greenComponent * 255)
        let red = UInt8(converted.redComponent * 255)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pointer[offset] = blue
                pointer[offset + 1] = green
                pointer[offset + 2] = red
                pointer[offset + 3] = 255
            }
        }
    }
}
