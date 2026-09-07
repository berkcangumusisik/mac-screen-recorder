import Foundation
import SwiftData

enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case image
    case video

    var displayName: String {
        self == .image ? String(localized: "Images") : String(localized: "Videos")
    }
}

/// History metadata for one capture.
///
/// Only *metadata* lives in the database — the path, size, a little text and a
/// pointer to a small thumbnail file. The media itself stays in the user's
/// output folder and is never copied into the store.
@Model
final class CaptureRecord {
    var path: String = ""
    var fileName: String = ""
    var kindRaw: String = CaptureKind.image.rawValue
    var createdAt: Date = Date.now
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var fileSize: Int = 0
    var isFavorite: Bool = false
    /// Locally recognised text, used only for searching this history.
    var recognizedText: String = ""
    var thumbnailFileName: String?

    init(path: String,
         fileName: String,
         kind: CaptureKind,
         createdAt: Date,
         pixelWidth: Int,
         pixelHeight: Int,
         fileSize: Int) {
        self.path = path
        self.fileName = fileName
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
    }

    var kind: CaptureKind {
        CaptureKind(rawValue: kindRaw) ?? .image
    }

    var url: URL { URL(fileURLWithPath: path) }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var pixelDescription: String {
        pixelWidth > 0 ? "\(pixelWidth) × \(pixelHeight)" : "—"
    }

    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        return fileName.lowercased().contains(needle)
            || recognizedText.lowercased().contains(needle)
    }
}
