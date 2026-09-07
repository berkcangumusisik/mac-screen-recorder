import SwiftUI

/// Local text recognition inside the editor: read the text out of a screenshot,
/// and get suggestions for things that probably should not be shared.
struct TextInspector: View {
    @ObservedObject var document: EditorDocument

    @State private var isScanning = false
    @State private var result: RecognizedTextResult?
    @State private var suggestions: [SensitiveSuggestion] = []
    @State private var selectedLines: Set<UUID> = []
    @State private var appliedSuggestions: Set<UUID> = []
    @State private var didScan = false

    private let service = TextRecognitionService()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Reading text…")).font(.callout)
                }
            }
            if let result, !result.isEmpty {
                textSection(result)
            } else if didScan && !isScanning {
                Text(String(localized: "No text was recognised in this image."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !suggestions.isEmpty {
                Divider()
                suggestionSection
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Text")).font(.headline)
            Text(String(localized: "Recognition runs on this Mac with Apple's Vision framework. Nothing is sent anywhere."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await scan() }
            } label: {
                Label(didScan ? String(localized: "Scan again") : String(localized: "Scan image for text"),
                      systemImage: "text.viewfinder")
            }
            .disabled(isScanning)
        }
    }

    private func textSection(_ result: RecognizedTextResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "\(result.lines.count) lines")).font(.subheadline)
                Spacer()
                Button(String(localized: "Copy all")) {
                    Clipboard.copy(text: result.fullText)
                }
                .controlSize(.small)
            }

            List(result.lines, selection: $selectedLines) { line in
                Text(line.text)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(height: 190)
            .listStyle(.bordered)

            Button(String(localized: "Copy selected")) {
                let text = result.lines
                    .filter { selectedLines.contains($0.id) }
                    .map(\.text)
                    .joined(separator: "\n")
                if !text.isEmpty { Clipboard.copy(text: text) }
            }
            .controlSize(.small)
            .disabled(selectedLines.isEmpty)
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Possibly sensitive")).font(.headline)
            Text(String(localized: "Pattern matching over the recognised text. It will miss things and it will flag harmless ones, so review each suggestion — nothing is hidden until you say so."))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(suggestions) { suggestion in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.kind.displayName)
                            .font(.caption.weight(.semibold))
                        Text(preview(of: suggestion.text))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(appliedSuggestions.contains(suggestion.id)
                           ? String(localized: "Added")
                           : String(localized: "Redact")) {
                        apply(suggestion)
                    }
                    .controlSize(.small)
                    .disabled(appliedSuggestions.contains(suggestion.id))
                }
                .padding(.vertical, 2)
            }

            Button(String(localized: "Redact all suggestions")) {
                for suggestion in suggestions where !appliedSuggestions.contains(suggestion.id) {
                    apply(suggestion)
                }
            }
            .controlSize(.small)
            .disabled(appliedSuggestions.count == suggestions.count)
        }
    }

    /// Shows enough to recognise the match without putting a full secret in the
    /// interface for longer than necessary.
    private func preview(of text: String) -> String {
        guard text.count > 12 else { return text }
        return text.prefix(6) + "…" + text.suffix(4)
    }

    private func scan() async {
        isScanning = true
        selectedLines.removeAll()
        appliedSuggestions.removeAll()
        defer { isScanning = false; didScan = true }

        let image = document.sourceImage
        let start = ContinuousClock.now
        do {
            async let text = service.recognize(in: image)
            async let regions = service.sensitiveRegions(in: image)
            result = try await text
            suggestions = try await regions
            Metrics.shared.record(MetricName.ocrPass, duration: start.secondsElapsed)
        } catch {
            ErrorPresenter.present((error as? SnapletError) ?? .ocrFailed(error.localizedDescription))
        }
    }

    private func apply(_ suggestion: SensitiveSuggestion) {
        let imageSize = CGSize(width: document.sourceImage.width, height: document.sourceImage.height)
        let rect = TextRecognitionService.pixelRect(suggestion.boundingBox, imageSize: imageSize)
        guard rect.width >= 2, rect.height >= 2 else { return }
        var annotation = document.makeAnnotation(kind: .redaction, frame: rect)
        annotation.strokeColor = RGBAColor(red: 0.06, green: 0.06, blue: 0.07)
        document.add(annotation)
        appliedSuggestions.insert(suggestion.id)
    }
}
