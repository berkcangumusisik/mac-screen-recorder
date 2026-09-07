import AppKit
import SwiftUI

/// A capture that has just happened and is waiting for the user to act on it.
@MainActor
final class PendingCapture: ObservableObject, Identifiable {
    let id = UUID()
    let result: CaptureResult
    @Published var savedURL: URL?
    /// Temporary file used for drag-and-drop when nothing was saved yet.
    private var dragURL: URL?

    init(result: CaptureResult, savedURL: URL?) {
        self.result = result
        self.savedURL = savedURL
    }

    var thumbnail: NSImage {
        NSImage(cgImage: result.image, size: result.pointSize)
    }

    /// A file URL suitable for dragging into another app, created on demand.
    func fileURLForDragging(format: ImageFormat, quality: Double) -> URL? {
        if let savedURL, FileManager.default.fileExists(atPath: savedURL.path) { return savedURL }
        if let dragURL, FileManager.default.fileExists(atPath: dragURL.path) { return dragURL }
        do {
            let data = try ImageExporter.data(from: result.image, format: format, quality: quality)
            let directory = TemporaryFiles.directory(named: "drag")
            let url = OutputNaming.uniqueURL(in: directory,
                                             fileName: OutputNaming.fileName(prefix: "Snaplet",
                                                                             date: result.capturedAt,
                                                                             fileExtension: format.fileExtension))
            try ImageExporter.write(data, to: url)
            dragURL = url
            return url
        } catch {
            Log.app.error("Could not stage drag file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// A small floating panel that never takes focus away from the app the user is
/// working in.
@MainActor
final class CapturePreviewController {

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    var onEdit: ((PendingCapture) -> Void)?
    var onSave: ((PendingCapture) -> Void)?
    var onCreateBugReport: ((PendingCapture) -> Void)?

    func show(_ capture: PendingCapture, autoDismissAfter seconds: TimeInterval = 9) {
        dismiss()

        let view = CapturePreviewView(capture: capture,
                                      onEdit: { [weak self] in self?.onEdit?(capture); self?.dismiss() },
                                      onSave: { [weak self] in self?.onSave?(capture) },
                                      onBugReport: { [weak self] in self?.onCreateBugReport?(capture); self?.dismiss() },
                                      onClose: { [weak self] in self?.dismiss() },
                                      onHoverChange: { [weak self] hovering in
                                          if hovering { self?.dismissTask?.cancel() }
                                      })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 190)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.screenUnderMouse ?? NSScreen.main {
            let inset: CGFloat = 24
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: frame.maxX - hosting.frame.width - inset,
                                         y: frame.minY + inset))
        }
        // orderFrontRegardless keeps the current app active — the preview must
        // never interrupt what the user is doing.
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}
