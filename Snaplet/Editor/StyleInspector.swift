import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StyleInspector: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject private var presets = StylePresetStore.shared
    @State private var newPresetName = ""

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case solid, gradient, image, transparent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .solid: return String(localized: "Solid")
            case .gradient: return String(localized: "Gradient")
            case .image: return String(localized: "Image")
            case .transparent: return String(localized: "None")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(String(localized: "Share-ready styling"), isOn: enabledBinding)
                .toggleStyle(.switch)

            if let style = document.style {
                presetPicker
                Divider()
                backgroundSection(style)
                Divider()
                layoutSection(style)
                Divider()
                captionSection(style)
                Divider()
                savePresetSection(style)
            } else {
                Text(String(localized: "Turn this on to place the screenshot on a background with padding, rounded corners and an optional caption."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { document.style != nil },
            set: { isOn in
                if isOn {
                    let id = SettingsStore.shared.preferences.defaultStylePresetID
                    document.applyStyle(presets.preset(withID: id))
                } else {
                    document.applyStyle(nil)
                }
            }
        )
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(String(localized: "Preset"), selection: presetSelection) {
                ForEach(presets.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            if let style = document.style, !style.isBuiltIn {
                Button(String(localized: "Delete this preset"), role: .destructive) {
                    presets.delete(id: style.id)
                    document.applyStyle(.clean)
                }
                .controlSize(.small)
            }
        }
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: { document.style?.id ?? StylePreset.clean.id },
            set: { document.applyStyle(presets.preset(withID: $0)) }
        )
    }

    // MARK: - Background

    private func backgroundSection(_ style: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Background")).font(.headline)
            Picker("", selection: backgroundKindBinding) {
                ForEach(BackgroundKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch style.background {
            case .solid(let color):
                ColorPicker(String(localized: "Colour"),
                            selection: Binding(get: { color.swiftUIColor },
                                               set: { new in update { $0.background = .solid(RGBAColor(NSColor(new))) } }))
            case .gradient(let start, let end, let angle):
                ColorPicker(String(localized: "From"),
                            selection: Binding(get: { start.swiftUIColor },
                                               set: { new in update { $0.background = .gradient(start: RGBAColor(NSColor(new)), end: end, angle: angle) } }))
                ColorPicker(String(localized: "To"),
                            selection: Binding(get: { end.swiftUIColor },
                                               set: { new in update { $0.background = .gradient(start: start, end: RGBAColor(NSColor(new)), angle: angle) } }))
                slider(String(localized: "Angle"),
                       value: Binding(get: { angle },
                                      set: { new in update { $0.background = .gradient(start: start, end: end, angle: new) } }),
                       range: 0...360,
                       format: { "\(Int($0))°" })
            case .image(let path):
                Text(path.isEmpty ? String(localized: "No image chosen")
                     : URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Choose image…"), action: chooseBackgroundImage)
                    .controlSize(.small)
            case .transparent:
                Text(String(localized: "Exports with a transparent background (PNG only)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(
            get: {
                switch document.style?.background {
                case .solid: return .solid
                case .gradient: return .gradient
                case .image: return .image
                case .transparent, .none: return .transparent
                }
            },
            set: { kind in
                update { style in
                    switch kind {
                    case .solid: style.background = .solid(RGBAColor(red: 0.95, green: 0.95, blue: 0.96))
                    case .gradient: style.background = .gradient(start: RGBAColor(red: 0.36, green: 0.42, blue: 0.86),
                                                                 end: RGBAColor(red: 0.62, green: 0.38, blue: 0.78),
                                                                 angle: 135)
                    case .image: style.background = .image(path: "")
                    case .transparent: style.background = .transparent
                    }
                }
            }
        )
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update { $0.background = .image(path: url.path) }
    }

    // MARK: - Layout

    private func layoutSection(_ style: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Layout")).font(.headline)
            slider(String(localized: "Padding"),
                   value: Binding(get: { style.paddingFraction }, set: { new in update { $0.paddingFraction = new } }),
                   range: 0...0.3,
                   format: { "\(Int($0 * 100))%" })
            slider(String(localized: "Corner radius"),
                   value: Binding(get: { style.cornerRadius }, set: { new in update { $0.cornerRadius = new } }),
                   range: 0...64,
                   format: { "\(Int($0)) px" })
            slider(String(localized: "Shadow"),
                   value: Binding(get: { style.shadow.opacity }, set: { new in update { $0.shadow.opacity = new } }),
                   range: 0...0.8,
                   format: { "\(Int($0 * 100))%" })
            Toggle(String(localized: "Window frame"),
                   isOn: Binding(get: { style.showsWindowFrame }, set: { new in update { $0.showsWindowFrame = new } }))
            Picker(String(localized: "Aspect ratio"),
                   selection: Binding(get: { style.aspect }, set: { new in update { $0.aspect = new } })) {
                ForEach(AspectPreset.allCases) { aspect in
                    Text(aspect.displayName).tag(aspect)
                }
            }
        }
    }

    private func captionSection(_ style: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Caption")).font(.headline)
            TextField(String(localized: "Title"),
                      text: Binding(get: { style.title }, set: { new in update { $0.title = new } }))
                .textFieldStyle(.roundedBorder)
            TextField(String(localized: "Short description"),
                      text: Binding(get: { style.subtitle }, set: { new in update { $0.subtitle = new } }))
                .textFieldStyle(.roundedBorder)
            ColorPicker(String(localized: "Text colour"),
                        selection: Binding(get: { style.textColor.swiftUIColor },
                                           set: { new in update { $0.textColor = RGBAColor(NSColor(new)) } }))
        }
    }

    private func savePresetSection(_ style: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Save as preset")).font(.headline)
            HStack {
                TextField(String(localized: "Name"), text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Save")) {
                    var preset = style
                    preset.id = UUID().uuidString
                    preset.name = newPresetName.isEmpty ? String(localized: "My style") : newPresetName
                    preset.isBuiltIn = false
                    presets.save(preset)
                    document.style = preset
                    newPresetName = ""
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func update(_ mutate: (inout StylePreset) -> Void) {
        guard var style = document.style else { return }
        mutate(&style)
        document.style = style
    }

    private func slider(_ title: String,
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
