import SwiftUI

extension Binding where Value == RGBAColor {
    /// Bridges the stored sRGB colour to SwiftUI's `ColorPicker`.
    var asColor: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.swiftUIColor },
            set: { wrappedValue = RGBAColor(NSColor($0)) }
        )
    }
}

struct AnnotationInspector: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selected = document.selectedAnnotation {
                selectedSection(selected)
                Divider()
            }
            defaultsSection
            if document.tool == .crop {
                Divider()
                cropSection
            }
            if isPrivacyContext {
                Divider()
                privacyNote
            }
            Spacer(minLength: 0)
        }
    }

    private var isPrivacyContext: Bool {
        EditorTool.privacyTools.contains(document.tool)
            || (document.selectedAnnotation?.kind.obscuresContent ?? false)
    }

    // MARK: - Selection

    @ViewBuilder
    private func selectedSection(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Selected: \(annotation.kind.displayName)"))
                .font(.headline)

            if annotation.kind == .text || annotation.kind == .callout {
                TextField(String(localized: "Text"), text: textBinding(annotation), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }

            ColorPicker(String(localized: "Colour"), selection: colorBinding(annotation).asColor)

            if annotation.kind == .magnifier {
                labelledSlider(String(localized: "Zoom"),
                               value: zoomBinding(annotation),
                               range: 1.2...4,
                               format: { String(format: "%.1f×", $0) })
            }

            if annotation.kind == .blur || annotation.kind == .pixelate {
                labelledSlider(annotation.kind == .blur
                               ? String(localized: "Blur radius")
                               : String(localized: "Block size"),
                               value: strengthBinding(annotation),
                               range: 4...80,
                               format: { "\(Int($0)) px" })
            }

            if annotation.kind == .text || annotation.kind == .callout {
                labelledSlider(String(localized: "Font size"),
                               value: fontBinding(annotation),
                               range: 10...160,
                               format: { "\(Int($0)) px" })
            }

            if !annotation.kind.obscuresContent {
                labelledSlider(String(localized: "Thickness"),
                               value: widthBinding(annotation),
                               range: 1...40,
                               format: { "\(Int($0)) px" })
            }

            HStack {
                Button(String(localized: "Bring to front")) { document.bringSelectedToFront() }
                Button(String(localized: "Delete"), role: .destructive) { document.deleteSelected() }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Defaults

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "New annotations"))
                .font(.headline)
            ColorPicker(String(localized: "Colour"), selection: $document.strokeColor.asColor)
            labelledSlider(String(localized: "Thickness"),
                           value: $document.lineWidth,
                           range: 1...40,
                           format: { "\(Int($0)) px" })
            labelledSlider(String(localized: "Font size"),
                           value: $document.fontSize,
                           range: 10...160,
                           format: { "\(Int($0)) px" })
            Toggle(String(localized: "Fill shapes"), isOn: $document.fillEnabled)
            if document.fillEnabled {
                ColorPicker(String(localized: "Fill colour"), selection: $document.fillColor.asColor)
            }
            if document.tool == .step {
                Text(String(localized: "Next number: \(document.nextStepNumber)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cropSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Crop"))
                .font(.headline)
            Text(String(localized: "Drag on the image, then press Return to apply."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "Reset to full image")) { document.resetCrop() }
                .disabled(!document.isCropped)
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Hiding sensitive content"), systemImage: "lock.shield")
                .font(.headline)
            Text(String(localized: "Redact draws an opaque block and is the recommended choice. Blur and pixelate are visual effects: enough to keep a screenshot tidy, but not a guarantee against reconstruction. Whatever you choose, exporting rasterises the result — the original pixels are not written into the exported file."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ annotation: Annotation,
                            _ keyPath: WritableKeyPath<Annotation, T>) -> Binding<T> {
        Binding(
            get: {
                document.annotations.first { $0.id == annotation.id }?[keyPath: keyPath]
                    ?? annotation[keyPath: keyPath]
            },
            set: { newValue in
                guard var updated = document.annotations.first(where: { $0.id == annotation.id }) else { return }
                updated[keyPath: keyPath] = newValue
                document.replace(updated)
            }
        )
    }

    private func textBinding(_ a: Annotation) -> Binding<String> { binding(a, \.text) }
    private func colorBinding(_ a: Annotation) -> Binding<RGBAColor> { binding(a, \.strokeColor) }
    private func widthBinding(_ a: Annotation) -> Binding<Double> { binding(a, \.lineWidth) }
    private func fontBinding(_ a: Annotation) -> Binding<Double> { binding(a, \.fontSize) }
    private func zoomBinding(_ a: Annotation) -> Binding<Double> { binding(a, \.zoom) }
    private func strengthBinding(_ a: Annotation) -> Binding<Double> { binding(a, \.effectStrength) }

    private func labelledSlider(_ title: String,
                                value: Binding<Double>,
                                range: ClosedRange<Double>,
                                format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(Text(title))
        }
    }
}

extension Annotation.Kind {
    var displayName: String {
        switch self {
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .freehand: return String(localized: "Drawing")
        case .highlighter: return String(localized: "Highlight")
        case .text: return String(localized: "Text")
        case .callout: return String(localized: "Callout")
        case .step: return String(localized: "Step number")
        case .magnifier: return String(localized: "Magnifier")
        case .blur: return String(localized: "Blur")
        case .pixelate: return String(localized: "Pixelate")
        case .redaction: return String(localized: "Redaction")
        }
    }
}
