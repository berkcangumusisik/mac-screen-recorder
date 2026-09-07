import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    let environment: AppEnvironment

    @ObservedObject private var settings = SettingsStore.shared
    @State private var inspectorTab: InspectorTab = .annotate
    @State private var zoom: Double = 0
    @State private var isExporting = false
    @State private var isTextFieldFocused = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case annotate, style
        var id: String { rawValue }
        var title: String {
            self == .annotate ? String(localized: "Annotate") : String(localized: "Style")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            toolPalette
            Divider()
            VStack(spacing: 0) {
                EditorCanvas(document: document, zoom: zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                bottomBar
            }
            Divider()
            inspector
                .frame(width: 268)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .snapletEditTextRequested)) { _ in
            inspectorTab = .annotate
            isTextFieldFocused = true
        }
    }

    // MARK: - Tools

    private var toolPalette: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(EditorTool.drawingTools) { tool in
                    toolButton(tool)
                }
                Divider().padding(.vertical, 4)
                ForEach(EditorTool.privacyTools) { tool in
                    toolButton(tool)
                }
            }
            .padding(8)
        }
        .frame(width: 56)
        .background(.bar)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        Button {
            document.tool = tool
        } label: {
            Image(systemName: tool.symbolName)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderless)
        .background(document.tool == tool ? Color.accentColor.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .help(tool.title)
        .accessibilityLabel(Text(tool.title))
        .accessibilityAddTraits(document.tool == tool ? [.isSelected] : [])
        .keyboardShortcut(KeyEquivalent(Character(tool.keyEquivalent)), modifiers: [])
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                document.undo()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help(String(localized: "Undo"))

            Button {
                document.redo()
            } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help(String(localized: "Redo"))

            Divider().frame(height: 16)

            Button { document.rotate(by: -1) } label: { Image(systemName: "rotate.left") }
                .help(String(localized: "Rotate left"))
            Button { document.rotate(by: 1) } label: { Image(systemName: "rotate.right") }
                .help(String(localized: "Rotate right"))

            if document.isCropped {
                Button(String(localized: "Reset crop")) { document.resetCrop() }
            }

            Spacer()

            Picker(String(localized: "Zoom"), selection: $zoom) {
                Text(String(localized: "Fit")).tag(0.0)
                Text("50%").tag(0.5)
                Text("100%").tag(1.0)
                Text("200%").tag(2.0)
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .labelsHidden()

            Text(sizeDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Button {
                copyToClipboard()
            } label: { Label(String(localized: "Copy"), systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Button {
                environment.openBugReport(forRenderedImage: renderedImage())
            } label: { Label(String(localized: "Bug report"), systemImage: "ladybug") }

            Button {
                exportWithPanel()
            } label: { Label(String(localized: "Export…"), systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sizeDescription: String {
        let size = document.renderRequest.croppedPixelSize
        if let style = document.style {
            let layout = PresentationRenderer.layout(contentSize: size, style: style)
            return "\(Int(layout.canvasSize.width)) × \(Int(layout.canvasSize.height)) px"
        }
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            ScrollView {
                switch inspectorTab {
                case .annotate:
                    AnnotationInspector(document: document)
                        .padding(12)
                case .style:
                    StyleInspector(document: document)
                        .padding(12)
                }
            }
        }
        .background(.bar)
    }

    // MARK: - Export

    private func renderedImage() -> CGImage? {
        document.renderedImage()
    }

    private func copyToClipboard() {
        guard let image = renderedImage() else {
            ErrorPresenter.present(.exportFailed("render produced no image"))
            return
        }
        Clipboard.copy(image: image)
    }

    private func exportWithPanel() {
        guard let image = renderedImage() else {
            ErrorPresenter.present(.exportFailed("render produced no image"))
            return
        }
        let format = settings.preferences.imageFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .png ? UTType.png : UTType.jpeg]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.ensureOutputDirectory()
        panel.nameFieldStringValue = OutputNaming.fileName(prefix: "Snaplet",
                                                           date: document.capturedAt,
                                                           fileExtension: format.fileExtension)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ImageExporter.data(from: image,
                                              format: format,
                                              quality: settings.preferences.jpegQuality)
            try ImageExporter.write(data, to: url)
            document.sourceURL = url
            environment.registerExport(url: url, image: image, capturedAt: document.capturedAt)
        } catch {
            ErrorPresenter.present((error as? SnapletError) ?? .exportFailed(error.localizedDescription))
        }
    }
}
