import Foundation

/// Scratch space for drag files, in-progress recordings and export staging.
///
/// Everything lives under one directory so a single sweep at launch and at
/// termination is enough to keep the disk clean.
enum TemporaryFiles {
    private static let rootName = "app.snaplet.Snaplet"

    static var root: URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func directory(named name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func file(named name: String, in subdirectory: String) -> URL {
        directory(named: subdirectory).appendingPathComponent(name)
    }

    /// Removes scratch files. `keeping` protects files that are still in use,
    /// such as an unfinished recording being recovered.
    static func sweep(keeping keep: Set<URL> = []) {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: root,
                                                              includingPropertiesForKeys: nil) else { return }
        for url in contents where !keep.contains(url) {
            try? manager.removeItem(at: url)
        }
    }
}
