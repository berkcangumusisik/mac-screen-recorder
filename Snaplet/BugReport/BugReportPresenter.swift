import AppKit
import SwiftUI

@MainActor
final class BugReportPresenter: NSObject, NSWindowDelegate {

    private unowned let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func present(image: CGImage?, mediaURL: URL?, stepCount: Int = 0) {
        // The screenshot needs to exist as a file before it can be exported
        // alongside the report.
        var attachments: [URL] = []
        if let mediaURL, FileManager.default.fileExists(atPath: mediaURL.path) {
            attachments.append(mediaURL)
        } else if let image {
            let directory = TemporaryFiles.directory(named: "bug-report")
            let url = OutputNaming.uniqueURL(in: directory,
                                             fileName: OutputNaming.fileName(prefix: "Snaplet",
                                                                             date: Date(),
                                                                             fileExtension: "png"))
            if let data = try? ImageExporter.data(from: image, format: .png) {
                try? ImageExporter.write(data, to: url)
                attachments.append(url)
            }
        }

        let view = BugReportView(attachments: attachments, stepCount: stepCount)
        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Create Bug Report")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 700))
            window.minSize = NSSize(width: 560, height: 600)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        } else if let hosting = window?.contentViewController as? NSHostingController<BugReportView> {
            hosting.rootView = view
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0 is NSPanel }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct BugReportView: View {
    let attachments: [URL]
    let stepCount: Int

    @State private var report = BugReport()
    @State private var includeAttachments = true
    @State private var confirmation: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Everything below stays on this Mac. Snaplet does not connect to GitHub and does not upload anything."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                field(String(localized: "Title"), text: $report.title)
                multilineField(String(localized: "Steps to reproduce"), text: $report.steps, lines: 4...8)
                multilineField(String(localized: "Expected behavior"), text: $report.expected, lines: 2...5)
                multilineField(String(localized: "Actual behavior"), text: $report.actual, lines: 2...5)

                environmentSection
                attachmentSection

                Divider()

                HStack {
                    Button {
                        Clipboard.copy(text: markdown)
                        confirmation = String(localized: "Markdown copied to the clipboard.")
                    } label: {
                        Label(String(localized: "Copy Markdown"), systemImage: "doc.on.doc")
                    }
                    Button {
                        exportFolder()
                    } label: {
                        Label(String(localized: "Export folder…"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }

                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                DisclosureGroup(String(localized: "Preview")) {
                    Text(markdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(18)
        }
        .onAppear {
            if report.steps.isEmpty, stepCount > 0 {
                report.steps = BugReport.stepDraft(markerCount: stepCount)
            }
        }
    }

    private var markdown: String {
        var copy = report
        copy.attachmentNames = includeAttachments ? attachments.map(\.lastPathComponent) : []
        return copy.markdown
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    private func multilineField(_ title: String,
                                text: Binding<String>,
                                lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(lines)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Environment")).font(.headline)
            Text(String(localized: "Only what you tick is included. Your computer name, account name and file paths are never added."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(BugReport.systemVersionLine, isOn: $report.includeSystemVersion)
            Toggle(BugReport.appVersionLine, isOn: $report.includeAppVersion)
            Toggle(BugReport.hardwareLine, isOn: $report.includeHardwareModel)
            TextField(String(localized: "Anything else worth adding"),
                      text: $report.extraEnvironment,
                      axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Media")).font(.headline)
            if attachments.isEmpty {
                Text(String(localized: "No media attached."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(String(localized: "List the media in the report"), isOn: $includeAttachments)
                ForEach(attachments, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "Exporting copies these files next to the Markdown so you can drag them into the issue yourself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Here")
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let name = report.title.isEmpty
            ? String(localized: "Snaplet bug report")
            : report.title.replacingOccurrences(of: "/", with: "-")
        var folder = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path), suffix < 100 {
            folder = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try markdown.write(to: folder.appendingPathComponent("report.md"),
                               atomically: true,
                               encoding: .utf8)
            if includeAttachments {
                for url in attachments {
                    let destination = folder.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: destination)
                }
            }
            confirmation = String(localized: "Exported to \(folder.lastPathComponent).")
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            ErrorPresenter.present(.fileWriteFailed(error.localizedDescription))
        }
    }
}
