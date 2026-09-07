import AppKit
import SwiftData

/// Local history of captures.
///
/// SwiftData is used because it is the lightweight local persistence built into
/// the OS: no third-party dependency, no server, and a schema that stays in
/// step with the Swift model. Large media never enters the database — items
/// hold a path plus a small thumbnail written next to the store.
@MainActor
final class LibraryStore: ObservableObject {

    static let shared = LibraryStore()

    @Published private(set) var items: [CaptureRecord] = []
    @Published private(set) var isAvailable = false

    private var container: ModelContainer?
    private var context: ModelContext?
    private let recognizer = TextRecognitionService()

    private init() {
        configure()
    }

    // MARK: - Storage locations

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Snaplet", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var thumbnailDirectory: URL {
        let directory = supportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func configure() {
        let storeURL = Self.supportDirectory.appendingPathComponent("Library.store")
        let configuration = ModelConfiguration(url: storeURL)
        do {
            let container = try ModelContainer(for: CaptureRecord.self, configurations: configuration)
            self.container = container
            self.context = container.mainContext
            isAvailable = true
            reload()
        } catch {
            Log.library.error("History unavailable: \(error.localizedDescription, privacy: .public)")
            isAvailable = false
        }
    }

    // MARK: - Reading

    func reload() {
        guard let context else { return }
        let descriptor = FetchDescriptor<CaptureRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        items = (try? context.fetch(descriptor)) ?? []
    }

    func filtered(query: String, kind: CaptureKind?, favouritesOnly: Bool) -> [CaptureRecord] {
        items.filter { item in
            (kind == nil || item.kind == kind)
                && (!favouritesOnly || item.isFavorite)
                && item.matches(query: query)
        }
    }

    // MARK: - Writing

    func record(url: URL, kind: CaptureKind, pixelSize: CGSize, capturedAt: Date, image: CGImage?) {
        guard SettingsStore.shared.preferences.historyEnabled, let context else { return }

        // Never create a second row for the same file.
        if let existing = items.first(where: { $0.path == url.path }) {
            existing.createdAt = capturedAt
            save()
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let item = CaptureRecord(path: url.path,
                               fileName: url.lastPathComponent,
                               kind: kind,
                               createdAt: capturedAt,
                               pixelWidth: Int(pixelSize.width),
                               pixelHeight: Int(pixelSize.height),
                               fileSize: (attributes?[.size] as? NSNumber)?.intValue ?? 0)
        context.insert(item)
        save()
        reload()

        if let image {
            writeThumbnail(image, for: item)
        } else if kind == .video {
            Task { [weak self] in
                guard let poster = await VideoThumbnail.firstFrame(of: url) else { return }
                self?.writeThumbnail(poster, for: item)
            }
        }

        if kind == .image, let image {
            indexText(of: image, for: item)
        }
    }

    private func writeThumbnail(_ image: CGImage, for item: CaptureRecord) {
        let longest = CGFloat(max(image.width, image.height))
        let factor = min(1, 320 / max(longest, 1))
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        guard let resized = ImageExporter.resized(image, to: size),
              let data = try? ImageExporter.data(from: resized, format: .jpeg, quality: 0.75) else { return }
        let name = "\(UUID().uuidString).jpg"
        let url = Self.thumbnailDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            item.thumbnailFileName = name
            save()
        } catch {
            Log.library.debug("Thumbnail not written")
        }
    }

    /// Runs Vision off the main thread and stores only the text, never logging it.
    private func indexText(of image: CGImage, for item: CaptureRecord) {
        Task { [weak self] in
            guard let self else { return }
            guard let result = try? await recognizer.recognize(in: image), !result.isEmpty else { return }
            item.recognizedText = result.fullText
            self.save()
        }
    }

    func thumbnail(for item: CaptureRecord) -> NSImage? {
        guard let name = item.thumbnailFileName else { return nil }
        return NSImage(contentsOf: Self.thumbnailDirectory.appendingPathComponent(name))
    }

    // MARK: - Mutations

    func toggleFavorite(_ item: CaptureRecord) {
        item.isFavorite.toggle()
        save()
    }

    /// Removes Snaplet's record. The file on disk is untouched.
    func removeFromHistory(_ item: CaptureRecord) {
        removeThumbnail(of: item)
        context?.delete(item)
        save()
        reload()
    }

    /// Moves the file to the Trash *and* removes the record.
    func moveFileToTrash(_ item: CaptureRecord) throws {
        if item.fileExists {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
        removeFromHistory(item)
    }

    func clearAll() {
        guard let context else { return }
        for item in items {
            removeThumbnail(of: item)
            context.delete(item)
        }
        save()
        reload()
    }

    private func removeThumbnail(of item: CaptureRecord) {
        guard let name = item.thumbnailFileName else { return }
        try? FileManager.default.removeItem(at: Self.thumbnailDirectory.appendingPathComponent(name))
        item.thumbnailFileName = nil
    }

    private func save() {
        do {
            try context?.save()
        } catch {
            Log.library.error("History save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
