import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Encoding and writing of still images. Everything here is pure and testable:
/// it never touches UI or user defaults.
enum ImageExporter {

    static func data(from image: CGImage, format: ImageFormat, quality: Double = 0.9) throws -> Data {
        let type: UTType = format == .png ? .png : .jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
                                                                type.identifier as CFString,
                                                                1,
                                                                nil) else {
            throw SnapletError.exportFailed("image destination unavailable")
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = max(0.1, min(1.0, quality))
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SnapletError.exportFailed("encoding failed")
        }
        return output as Data
    }

    /// Writes atomically so a crash or a full disk never leaves a truncated file
    /// where a valid image is expected.
    static func write(_ data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            if (error as NSError).code == NSFileWriteOutOfSpaceError {
                throw SnapletError.diskFull
            }
            throw SnapletError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Rasterises to a fixed pixel size using a fresh sRGB bitmap context.
    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Pasteboard access, kept in one place so "copy" always means the same thing.
enum Clipboard {

    static func copy(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = try? ImageExporter.data(from: image, format: .png) {
            item.setData(png, forType: .png)
        }
        let representation = NSBitmapImageRep(cgImage: image)
        if let tiff = representation.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
    }

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Reads an image from the pasteboard, preferring lossless PNG/TIFF data.
    static func image() -> CGImage? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return image
            }
        }
        guard let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let first = objects.first else { return nil }
        var rect = CGRect(origin: .zero, size: first.size)
        return first.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Deterministic, collision-free output names.
enum OutputNaming {
    static func fileName(prefix: String, date: Date, fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(fileExtension)"
    }

    /// Appends " 2", " 3", … until the name is free.
    static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2
        while index < 1000 {
            let candidate = directory.appendingPathComponent("\(base) \(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
        return directory.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }
}

/// Free-space checks so Snaplet can fail early rather than half-way through a
/// long recording or export.
enum DiskSpace {
    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func hasAtLeast(_ bytes: Int64, at url: URL) -> Bool {
        guard let available = availableBytes(at: url) else { return true }
        return available >= bytes
    }
}
