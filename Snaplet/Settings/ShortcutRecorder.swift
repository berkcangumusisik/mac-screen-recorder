import AppKit
import SwiftUI

/// Click-to-record control for a single global shortcut.
///
/// While recording, key events are consumed locally so the shortcut being typed
/// does not also trigger whatever it is currently bound to.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut?
    var accessibilityLabel: String

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.onChange = { newValue in shortcut = newValue }
        view.setAccessibilityLabel(accessibilityLabel)
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        if !nsView.isRecording { nsView.shortcut = shortcut }
        nsView.setAccessibilityLabel(accessibilityLabel)
    }
}

final class ShortcutRecorderView: NSView {

    var onChange: ((KeyboardShortcut?) -> Void)?

    var shortcut: KeyboardShortcut? {
        didSet { needsDisplay = true }
    }

    private(set) var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording { installMonitor() } else { removeMonitor() }
        }
    }

    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording.toggle()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = String(localized: "Press keys…")
        } else if let shortcut {
            text = shortcut.displayString
        } else {
            text = String(localized: "Not set")
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: shortcut == nil && !isRecording ? NSColor.tertiaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
        setAccessibilityValue(text)
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns `true` when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return true }

        if event.keyCode == 53 { // Escape cancels
            isRecording = false
            return true
        }
        if event.keyCode == 51 { // Delete clears
            shortcut = nil
            onChange?(nil)
            isRecording = false
            return true
        }

        let candidate = KeyboardShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
        guard candidate.isAcceptable else {
            NSSound.beep()
            return true
        }
        shortcut = candidate
        onChange?(candidate)
        isRecording = false
        return true
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
