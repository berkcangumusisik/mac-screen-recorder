import AppKit

enum LibraryItemKind: String, Codable, Sendable {
    case image
    case video
}

/// Placeholder store. Replaced by the SwiftData-backed library in the library
/// commit.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    func record(url: URL, kind: LibraryItemKind, pixelSize: CGSize, capturedAt: Date, image: CGImage?) {}
    func clearAll() {}
}
