import AppKit
import SwiftUI

/// Contents of the floating capture preview.
struct CapturePreviewView: View {
    @ObservedObject var capture: PendingCapture
    @ObservedObject private var settings = SettingsStore.shared

    let onEdit: () -> Void
    let onSave: () -> Void
    let onBugReport: () -> Void
    let onPin: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            thumbnail
            actions
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close preview", comment: "Preview panel close button"))
        }
    }

    private var thumbnail: some View {
        Image(nsImage: capture.thumbnail)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 108)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .onDrag {
                let format = settings.preferences.imageFormat
                guard let url = capture.fileURLForDragging(format: format,
                                                           quality: settings.preferences.jpegQuality),
                      let provider = NSItemProvider(contentsOf: url) else {
                    return NSItemProvider()
                }
                return provider
            }
            .help(String(localized: "Drag to copy the file into another app"))
            .accessibilityLabel(Text("Captured image, \(pixelDescription). Drag to copy the file.",
                                     comment: "Preview thumbnail accessibility label"))
    }

    /// One control group: the next step people actually take is Edit, so it
    /// carries the emphasis and the rest sit at equal weight beside it.
    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil.tip.crop.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("e", modifiers: [])
            .help(String(localized: "Open in the editor"))

            if capture.savedURL == nil {
                Button(action: onSave) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help(String(localized: "Save to the output folder"))
            } else {
                Button {
                    if let url = capture.savedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help(String(localized: "Show in Finder"))
            }

            if capture.kind == .image {
                Button(action: onPin) {
                    Label("Pin to screen", systemImage: "pin")
                }
                .help(String(localized: "Keep this on top of every window"))
            }

            Spacer(minLength: 0)

            Menu {
                Button("Copy Again") { Clipboard.copy(image: capture.result.image) }
                Button("Create Bug Report…", action: onBugReport)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "More actions"))
            .accessibilityLabel(Text("More actions", comment: "Preview overflow menu"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var pixelDescription: String {
        "\(capture.result.image.width) × \(capture.result.image.height)"
    }

    private var statusText: String {
        if let url = capture.savedURL {
            return url.lastPathComponent
        }
        return String(localized: "Copied to clipboard")
    }
}
