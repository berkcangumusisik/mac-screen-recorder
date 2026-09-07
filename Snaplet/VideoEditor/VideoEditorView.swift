import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorView: View {
    @StateObject private var document: VideoDocument
    @StateObject private var exporter = VideoExporter()
    @ObservedObject private var settings = SettingsStore.shared

    private let environment: AppEnvironment
    @State private var placementKind: VideoOverlayEditor.PlacementKind?
    @State private var gifOptions = GIFExportOptions()

    init(url: URL, environment: AppEnvironment) {
        _document = StateObject(wrappedValue: VideoDocument(url: url))
        self.environment = environment
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                preview
                Divider()
                transport
                VideoTimelineView(document: document)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                Divider()
                exportBar
            }
            Divider()
            inspector.frame(width: 288)
        }
        .frame(minWidth: 900, minHeight: 620)
        .task { await document.load() }
        .alert(item: errorBinding) { error in
            Alert(title: Text(error.message))
        }
    }

    private var errorBinding: Binding<IdentifiableMessage?> {
        Binding(
            get: { document.loadError.map { IdentifiableMessage(message: $0.localizedDescription) } },
            set: { _ in }
        )
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            Color.black
            VideoPlayerView(player: document.player)
            VideoOverlayEditor(document: document, placementKind: $placementKind)
            if !document.isLoaded {
                ProgressView().controlSize(.large)
            }
            if placementKind != nil {
                VStack {
                    Spacer()
                    Text(String(localized: "Drag on the video to place it"))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 14)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                document.togglePlayback()
            } label: {
                Image(systemName: document.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(Text(document.isPlaying ? "Pause" : "Play"))

            Text("\(TimeFormatting.timecode(document.currentTime)) / \(TimeFormatting.timecode(document.duration))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            ForEach([VideoOverlayEditor.PlacementKind.text, .redaction, .zoom]) { kind in
                Button {
                    placementKind = placementKind == kind ? nil : kind
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
                .background(placementKind == kind ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .help(kind.title)
            }

            Spacer()

            Button {
                Task { await extractFrame() }
            } label: {
                Label(String(localized: "Save frame"), systemImage: "camera")
            }
            .disabled(!document.isLoaded)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Export

    private var exportBar: some View {
        HStack(spacing: 12) {
            if exporter.isExporting {
                ProgressView(value: exporter.progress)
                    .frame(width: 180)
                Text("\(Int(exporter.progress * 100))%")
                    .font(.caption.monospacedDigit())
                Button(String(localized: "Cancel")) { exporter.cancel() }
            } else {
                Text(String(localized: "Trimmed length: \(TimeFormatting.timecode(document.edit.trimmedDuration))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await exportGIF() }
                } label: {
                    Label(String(localized: "Export GIF…"), systemImage: "square.stack.3d.down.right")
                }
                .disabled(!document.isLoaded)

                Button {
                    Task { await exportMovie() }
                } label: {
                    Label(String(localized: "Export MP4…"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!document.isLoaded)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                trimSection
                if document.selectedOverlay != nil || document.selectedZoom != nil {
                    Divider()
                    selectionSection
                }
                Divider()
                gifSection
                Divider()
                styleSection
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .background(.bar)
    }

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Trim")).font(.headline)
            HStack {
                Button(String(localized: "Start here")) { document.edit.trimStart = min(document.currentTime, document.edit.trimEnd - 0.2) }
                Button(String(localized: "End here")) { document.edit.trimEnd = max(document.currentTime, document.edit.trimStart + 0.2) }
            }
            .controlSize(.small)
            Text("\(TimeFormatting.timecode(document.edit.trimStart)) → \(TimeFormatting.timecode(document.edit.trimEnd))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Picker(String(localized: "Resolution"), selection: $document.edit.resolutionCap) {
                ForEach(ResolutionCap.allCases) { cap in
                    Text(cap.displayName).tag(cap)
                }
            }
        }
    }

    @ViewBuilder
    private var selectionSection: some View {
        if let overlay = document.selectedOverlay {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Selected: \(overlay.kind.displayName)")).font(.headline)
                if overlay.kind == .text {
                    TextField(String(localized: "Text"),
                              text: Binding(get: { overlay.text },
                                            set: { var copy = overlay; copy.text = $0; document.update(copy) }),
                              axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                }
                timeRangeControls(start: overlay.start, end: overlay.end) { start, end in
                    var copy = overlay
                    copy.start = start
                    copy.end = end
                    document.update(copy)
                }
                if overlay.kind == .redaction {
                    Text(String(localized: "The block is drawn into every exported frame in this range, before any zoom is applied."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "Delete"), role: .destructive) { document.deleteSelection() }
                    .controlSize(.small)
            }
        } else if let zoom = document.selectedZoom {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Selected: zoom")).font(.headline)
                timeRangeControls(start: zoom.start, end: zoom.end) { start, end in
                    var copy = zoom
                    copy.start = start
                    copy.end = end
                    document.update(copy)
                }
                Text(String(localized: "Magnification: \(String(format: "%.1f×", zoom.maximumScale))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Delete"), role: .destructive) { document.deleteSelection() }
                    .controlSize(.small)
            }
        }
    }

    private func timeRangeControls(start: Double,
                                   end: Double,
                                   update: @escaping (Double, Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(String(localized: "Start here")) { update(min(document.currentTime, end - 0.2), end) }
                Button(String(localized: "End here")) { update(start, max(document.currentTime, start + 0.2)) }
            }
            .controlSize(.small)
            Text("\(TimeFormatting.timecode(start)) → \(TimeFormatting.timecode(end))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var gifSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "GIF")).font(.headline)
            Picker(String(localized: "Frame rate"), selection: $gifOptions.frameRate) {
                Text("8 FPS").tag(8)
                Text("12 FPS").tag(12)
                Text("15 FPS").tag(15)
            }
            Picker(String(localized: "Width"), selection: $gifOptions.maximumWidth) {
                Text("480 px").tag(480)
                Text("640 px").tag(640)
                Text("800 px").tag(800)
            }
            Text(String(localized: "GIF export is limited to the first \(Int(GIFExportOptions.maximumDuration)) seconds of the trimmed range."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "Share-ready styling"),
                   isOn: Binding(
                    get: { document.edit.style != nil },
                    set: { isOn in
                        document.edit.style = isOn
                            ? StylePresetStore.shared.preset(withID: settings.preferences.defaultStylePresetID)
                            : nil
                    }))
            if document.edit.style != nil {
                Picker(String(localized: "Preset"),
                       selection: Binding(get: { document.edit.style?.id ?? "clean" },
                                          set: { document.edit.style = StylePresetStore.shared.preset(withID: $0) })) {
                    ForEach(StylePresetStore.shared.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                Picker(String(localized: "Aspect ratio"),
                       selection: Binding(get: { document.edit.style?.aspect ?? .original },
                                          set: { new in document.edit.style?.aspect = new })) {
                    ForEach(AspectPreset.allCases) { aspect in
                        Text(aspect.displayName).tag(aspect)
                    }
                }
                let canvas = document.edit.canvasSize(forSource: document.sourceSize)
                Text("\(Int(canvas.width)) × \(Int(canvas.height)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func extractFrame() async {
        guard let image = await document.extractFrame(at: document.currentTime) else {
            ErrorPresenter.present(.exportFailed("that frame could not be rendered"))
            return
        }
        let result = CaptureResult(image: image,
                                   scale: 1,
                                   source: .importedFile(document.url))
        environment.editorPresenter.present(result, savedURL: nil)
    }

    private func exportMovie() async {
        guard let url = savePanelURL(fileExtension: "mp4", type: .mpeg4Movie) else { return }
        do {
            let output = try await exporter.exportMovie(asset: document.asset,
                                                        edit: document.edit,
                                                        sourceSize: document.sourceSize,
                                                        frameRate: document.frameRate,
                                                        to: url)
            environment.library.record(url: output,
                                       kind: .video,
                                       pixelSize: document.edit.canvasSize(forSource: document.sourceSize),
                                       capturedAt: Date(),
                                       image: nil)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch let error as SnapletError {
            ErrorPresenter.present(error)
        } catch {
            ErrorPresenter.present(.exportFailed(error.localizedDescription))
        }
    }

    private func exportGIF() async {
        guard let url = savePanelURL(fileExtension: "gif", type: .gif) else { return }
        do {
            let output = try await exporter.exportGIF(asset: document.asset,
                                                      edit: document.edit,
                                                      sourceSize: document.sourceSize,
                                                      options: gifOptions,
                                                      to: url)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch let error as SnapletError {
            ErrorPresenter.present(error)
        } catch {
            ErrorPresenter.present(.exportFailed(error.localizedDescription))
        }
    }

    private func savePanelURL(fileExtension: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.ensureOutputDirectory()
        panel.nameFieldStringValue = OutputNaming.fileName(prefix: "Snaplet",
                                                           date: Date(),
                                                           fileExtension: fileExtension)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

struct IdentifiableMessage: Identifiable {
    let id = UUID()
    let message: String
}
