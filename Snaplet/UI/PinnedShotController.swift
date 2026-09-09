import AppKit
import SwiftUI

/// Keeps captures floating above every other window.
///
/// Pinning is the one feature people reach for constantly in this category:
/// keep a reference next to the thing you are rebuilding, compare two states,
/// or park a value you need to retype. Snaplet's windows are excluded from
/// capture, so a pinned shot never lands in the next screenshot.
@MainActor
final class PinnedShotController {

    private var panels: [NSPanel] = []
    private var cascadeStep = 0

    var count: Int { panels.count }

    func pin(image: CGImage, scale: CGFloat, capturedAt: Date = Date()) {
        let shot = PinnedShot(image: image, scale: scale, capturedAt: capturedAt)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: shot.initialSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)

        let view = PinnedShotView(shot: shot,
                                  onClose: { [weak self, weak panel] in
                                      guard let panel else { return }
                                      self?.close(panel)
                                  })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: shot.initialSize)

        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrameOrigin(nextOrigin(for: shot.initialSize))

        // orderFrontRegardless keeps the app the user is working in active.
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    /// Cascades so several pins do not land on top of each other.
    private func nextOrigin(for size: CGSize) -> CGPoint {
        guard let screen = NSScreen.screenUnderMouse ?? NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let offset = CGFloat(cascadeStep % 8) * 28
        cascadeStep += 1
        return CGPoint(x: min(visible.maxX - size.width - 32 - offset, visible.maxX - size.width - 8),
                       y: max(visible.minY + 8, visible.maxY - size.height - 64 - offset))
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panels.removeAll { $0 === panel }
    }

    func closeAll() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        cascadeStep = 0
    }
}

/// One pinned capture and the sizes it can be shown at.
@MainActor
final class PinnedShot: ObservableObject {
    let image: CGImage
    let scale: CGFloat
    let capturedAt: Date

    /// 1.0 shows the capture at the size it occupied on screen.
    @Published var zoom: Double = 1

    private var dragURL: URL?

    init(image: CGImage, scale: CGFloat, capturedAt: Date) {
        self.image = image
        self.scale = scale > 0 ? scale : 2
        self.capturedAt = capturedAt
    }

    var naturalSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    /// Large captures are pinned scaled down; nothing is ever enlarged to start.
    var initialSize: CGSize {
        let natural = naturalSize
        guard let screen = NSScreen.main else { return natural }
        let limit = CGSize(width: screen.visibleFrame.width * 0.6,
                           height: screen.visibleFrame.height * 0.6)
        let factor = min(1, min(limit.width / natural.width, limit.height / natural.height))
        return CGSize(width: (natural.width * factor).rounded(),
                      height: (natural.height * factor).rounded())
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: naturalSize) }

    var pixelDescription: String { "\(image.width) × \(image.height)" }

    /// A file to drag into another app, created on demand.
    func fileURLForDragging() -> URL? {
        if let dragURL, FileManager.default.fileExists(atPath: dragURL.path) { return dragURL }
        do {
            let data = try ImageExporter.data(from: image, format: .png)
            let directory = TemporaryFiles.directory(named: "pinned")
            let url = OutputNaming.uniqueURL(in: directory,
                                             fileName: OutputNaming.fileName(prefix: "Snaplet",
                                                                             date: capturedAt,
                                                                             fileExtension: "png"))
            try ImageExporter.write(data, to: url)
            dragURL = url
            return url
        } catch {
            Log.app.error("Could not stage pinned drag file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

struct PinnedShotView: View {
    @ObservedObject var shot: PinnedShot
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(nsImage: shot.nsImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18))
            )
            .overlay(alignment: .top) { toolbar }
            .onHover { isHovering = $0 }
            .onDrag {
                guard let url = shot.fileURLForDragging(),
                      let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
                return provider
            }
            .accessibilityLabel(Text("Pinned capture, \(shot.pixelDescription) pixels"))
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help(String(localized: "Close pin"))
            .accessibilityLabel(Text("Close pin"))

            Button {
                Clipboard.copy(image: shot.image)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help(String(localized: "Copy"))
            .accessibilityLabel(Text("Copy"))

            Spacer(minLength: 8)

            Text(shot.pixelDescription)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .padding(6)
        .opacity(isHovering ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
