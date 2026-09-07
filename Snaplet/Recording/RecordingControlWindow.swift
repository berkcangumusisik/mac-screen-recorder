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

    func show() {
        guard panel == nil else { return }
        model.onStop = { [weak self] in self?.onStop?() }

        let hosting = NSHostingView(rootView: RecordingControlView(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 190, height: 46)

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

    func update(elapsed: TimeInterval, isCountingDown: Bool, countdown: Int) {
        model.elapsed = elapsed
        model.isCountingDown = isCountingDown
        model.countdown = countdown
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
    var onStop: (() -> Void)?
}

struct RecordingControlView: View {
    @ObservedObject var model: RecordingControlModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isCountingDown ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(model.isCountingDown
                 ? String(localized: "Starting in \(model.countdown)")
                 : TimeFormatting.clock(model.elapsed))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .accessibilityLabel(model.isCountingDown
                                    ? Text("Recording starts in \(model.countdown) seconds")
                                    : Text("Recording, \(TimeFormatting.spoken(model.elapsed))"))

            Spacer(minLength: 0)

            Button {
                model.onStop?()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text("Stop recording"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
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
