import AppKit

/// Handles the "copy text on screen" shortcut.
@MainActor
final class TextRecognitionPresenter {

    private let service = TextRecognitionService()

    func copyText(from image: CGImage) async {
        let start = ContinuousClock.now
        do {
            let result = try await service.recognize(in: image)
            Metrics.shared.record(MetricName.ocrPass, duration: start.secondsElapsed)
            guard !result.isEmpty else {
                notify(String(localized: "No text found in that area."))
                return
            }
            Clipboard.copy(text: result.fullText)
            notify(String(localized: "Copied \(result.lines.count) lines of text."))
        } catch {
            ErrorPresenter.present((error as? SnapletError) ?? .ocrFailed(error.localizedDescription))
        }
    }

    /// A short, non-blocking confirmation. Recognised text is never logged.
    private func notify(_ message: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 12, width: 236, height: 20)
        let container = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.addSubview(label)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        if let screen = NSScreen.screenUnderMouse ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: frame.midX - 130, y: frame.minY + 90))
        }
        panel.orderFrontRegardless()

        Task {
            try? await Task.sleep(for: .seconds(2))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}
