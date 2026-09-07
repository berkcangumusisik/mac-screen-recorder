import OSLog

/// Central logging. Snaplet never logs captured pixels, OCR text, file contents
/// or window titles — only lifecycle and error information.
enum Log {
    private static let subsystem = "app.snaplet.Snaplet"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
