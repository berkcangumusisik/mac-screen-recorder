import AppKit
import SwiftUI

/// Small always-on-top control shown while recording.
///
/// Snaplet excludes its own windows from capture, so this control and the
/// countdown never appear in the recorded file.
@MainActor
final class RecordingControlWindow {

    private var panel: NSPanel?
    private let model = RecordingControlModel()

    var onStop: (() -> Void)?
    var onTogglePause: (() -> Void)?

    func show() {
        guard panel == nil else { return }
        model.onStop = { [weak self] in self?.onStop?() }
        model.onTogglePause = { [weak self] in self?.onTogglePause?() }

        let hosting = NSHostingView(rootView: RecordingControlView(model: model))
        // Sized to its content rather than a fixed width: the countdown label is
        // noticeably longer in some languages and was being clipped.
        let fitting = hosting.fittingSize
        hosting.frame = CGRect(x: 0, y: 0,
                               width: max(200, ceil(fitting.width)),
                               height: max(44, ceil(fitting.height)))

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if let screen = NSScreen.screenUnderMouse ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: frame.midX - hosting.frame.width / 2,
                                         y: frame.minY + 28))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(elapsed: TimeInterval,
                isCountingDown: Bool,
                countdown: Int,
                isPaused: Bool = false) {
        let wasCountingDown = model.isCountingDown
        model.elapsed = elapsed
        model.isCountingDown = isCountingDown
        model.countdown = countdown
        model.isPaused = isPaused

        // The countdown label and the timer are different lengths, so the panel
        // is re-measured when it swaps between them.
        if wasCountingDown != isCountingDown { resizeToFitContent() }
    }

    private func resizeToFitContent() {
        guard let panel, let hosting = panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }
        var frame = panel.frame
        let size = CGSize(width: max(200, ceil(fitting.width)), height: max(44, ceil(fitting.height)))
        // Keep it anchored where the user left it.
        frame.origin.x -= (size.width - frame.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

@MainActor
final class RecordingControlModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var isCountingDown = false
    @Published var countdown = 0
    @Published var isPaused = false
    var onStop: (() -> Void)?
    var onTogglePause: (() -> Void)?
}

struct RecordingControlView: View {
    @ObservedObject var model: RecordingControlModel

    /// A quiet pulse while recording is the clearest "this is live" signal that
    /// does not draw the eye away from what is being recorded.
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            label
            if !model.isCountingDown {
                pauseButton
            }
            stopButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .onAppear { isPulsing = true }
    }

    private var statusColor: Color {
        if model.isCountingDown { return .orange }
        return model.isPaused ? .yellow : .red
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .opacity(model.isPaused || model.isCountingDown ? 1 : (isPulsing ? 1 : 0.35))
            .animation(model.isPaused || model.isCountingDown
                       ? .default
                       : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: isPulsing)
            .accessibilityHidden(true)
    }

    private var label: some View {
        Text(text)
            .font(.system(.body, design: .monospaced).weight(.medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var text: String {
        if model.isCountingDown { return String(localized: "Starting in \(model.countdown)") }
        return TimeFormatting.clock(model.elapsed)
    }

    private var accessibilityLabel: String {
        if model.isCountingDown {
            return String(localized: "Recording starts in \(model.countdown) seconds")
        }
        if model.isPaused {
            return String(localized: "Paused at \(TimeFormatting.spoken(model.elapsed))")
        }
        return String(localized: "Recording, \(TimeFormatting.spoken(model.elapsed))")
    }

    private var pauseButton: some View {
        Button {
            model.onTogglePause?()
        } label: {
            Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                .frame(width: 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(model.isPaused ? String(localized: "Resume") : String(localized: "Pause"))
        .accessibilityLabel(Text(model.isPaused ? "Resume recording" : "Pause recording"))
    }

    private var stopButton: some View {
        Button {
            model.onStop?()
        } label: {
            Image(systemName: "stop.fill")
                .foregroundStyle(.red)
                .frame(width: 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(String(localized: "Stop"))
        .accessibilityLabel(Text("Stop recording"))
    }
}

enum TimeFormatting {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Used by VoiceOver, where "01:23" would be read as a pair of numbers.
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return String(localized: "\(minutes) minutes \(secs) seconds")
        }
        return String(localized: "\(secs) seconds")
    }

    /// Compact timecode used in the video editor, e.g. `01:23.4`.
    static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let secs = Int(clamped) % 60
        let tenths = Int((clamped - floor(clamped)) * 10)
        return String(format: "%02d:%02d.%d", minutes, secs, tenths)
    }
}
