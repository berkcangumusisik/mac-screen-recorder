import AppKit
import SwiftUI

/// Composition root. Every long-lived service is created here exactly once and
/// handed to the pieces that need it.
@MainActor
final class AppEnvironment: ObservableObject, CaptureCoordinatorDelegate {

    let settings = SettingsStore.shared
    let permissions = PermissionsService.shared
    let library = LibraryStore.shared
    let captureCoordinator = CaptureCoordinator()
    let previewController = CapturePreviewController()

    private(set) var menuBar: MenuBarController?

    lazy var editorPresenter = EditorPresenter(environment: self)
    lazy var recordingPresenter = RecordingPresenter(environment: self)
    lazy var textRecognitionPresenter = TextRecognitionPresenter()
    lazy var bugReportPresenter = BugReportPresenter(environment: self)
    lazy var libraryWindow = LibraryWindowController(environment: self)
    private var settingsWindow: SettingsWindowController?
    private var helpWindow: HelpWindowController?

    /// The menu bar asks for this every time the menu opens.
    var recordingMenuTitle: String { recordingPresenter.menuTitle }

    // MARK: - Lifecycle

    func start() {
        TemporaryFiles.sweep()
        settings.applyAppearance()
        captureCoordinator.delegate = self
        menuBar = MenuBarController(environment: self)

        previewController.onEdit = { [weak self] capture in self?.openEditor(for: capture) }
        previewController.onSave = { [weak self] capture in self?.saveOnDemand(capture) }
        previewController.onCreateBugReport = { [weak self] capture in self?.openBugReport(for: capture) }

        HotkeyManager.shared.setHandler { [weak self] action in
            self?.perform(action)
        }
        reloadHotkeys()
    }

    func stop() {
        HotkeyManager.shared.unregisterAll()
        previewController.dismiss()
        TemporaryFiles.sweep()
    }

    func reloadHotkeys() {
        let failures = HotkeyManager.shared.apply(settings.preferences.resolvedShortcuts)
        guard !failures.isEmpty else { return }
        let description = failures
            .map { "\($0.key.title): \($0.value)" }
            .sorted()
            .joined(separator: "\n")
        Log.hotkeys.notice("Shortcut registration issues: \(description, privacy: .public)")
    }

    /// Reported by the Shortcuts settings pane so the user sees which bindings
    /// the system refused.
    var hotkeyFailures: [HotkeyAction: String] { HotkeyManager.shared.failures }

    // MARK: - Actions

    func perform(_ action: HotkeyAction) {
        switch action {
        case .captureArea:
            Task { await captureCoordinator.captureArea() }
        case .captureWindow:
            Task { await captureCoordinator.captureWindow() }
        case .captureFullScreen:
            Task { await captureCoordinator.captureFullScreen() }
        case .repeatLastArea:
            Task { await captureCoordinator.repeatLastArea() }
        case .toggleRecording:
            toggleRecording()
        case .copyTextOnScreen:
            Task { await copyTextOnScreen() }
        case .editClipboardImage:
            editClipboardImage()
        }
    }

    // MARK: - CaptureCoordinatorDelegate

    func captureCoordinator(_ coordinator: CaptureCoordinator, didProduce result: CaptureResult) {
        deliver(result)
    }

    func captureCoordinator(_ coordinator: CaptureCoordinator, didFail error: SnapletError) {
        ErrorPresenter.present(error)
    }

    // MARK: - Delivery

    /// Clipboard first — that is the fastest path to "I have the screenshot" —
    /// then optional disk write, then the preview.
    func deliver(_ result: CaptureResult) {
        let preferences = settings.preferences

        if preferences.copyImageToClipboard {
            Clipboard.copy(image: result.image)
        }

        var savedURL: URL?
        if preferences.autoSaveToDisk {
            savedURL = writeToDisk(result)
        }

        if preferences.playCaptureSound {
            NSSound(named: "Tink")?.play()
        }

        let pending = PendingCapture(result: result, savedURL: savedURL)
        recordInLibrary(pending)

        if preferences.showPreviewPanel {
            previewController.show(pending)
        }
    }

    @discardableResult
    private func writeToDisk(_ result: CaptureResult) -> URL? {
        let preferences = settings.preferences
        let directory = settings.ensureOutputDirectory()
        do {
            let data = try ImageExporter.data(from: result.image,
                                              format: preferences.imageFormat,
                                              quality: preferences.jpegQuality)
            guard DiskSpace.hasAtLeast(Int64(data.count) + 8_000_000, at: directory) else {
                throw SnapletError.diskFull
            }
            let name = OutputNaming.fileName(prefix: "Snaplet",
                                             date: result.capturedAt,
                                             fileExtension: preferences.imageFormat.fileExtension)
            let url = OutputNaming.uniqueURL(in: directory, fileName: name)
            try ImageExporter.write(data, to: url)
            return url
        } catch {
            ErrorPresenter.present((error as? SnapletError) ?? .fileWriteFailed(error.localizedDescription))
            return nil
        }
    }

    private func saveOnDemand(_ capture: PendingCapture) {
        guard capture.savedURL == nil else { return }
        capture.savedURL = writeToDisk(capture.result)
    }

    // MARK: - Windows

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(environment: self)
        }
        settingsWindow?.show()
    }

    func showHelp() {
        if helpWindow == nil {
            helpWindow = HelpWindowController(environment: self)
        }
        helpWindow?.show()
    }

    // MARK: - Stage hooks
    // These are filled in by the later stages; each one is wired to real
    // behaviour before it is offered anywhere in the UI.

    func showHistory() {
        libraryWindow.show()
    }

    func openEditor(for capture: PendingCapture) {
        editorPresenter.present(capture.result, savedURL: capture.savedURL)
    }

    func openBugReport(for capture: PendingCapture) {
        bugReportPresenter.present(image: capture.result.image, mediaURL: capture.savedURL)
    }

    func openBugReport(forRenderedImage image: CGImage?) {
        bugReportPresenter.present(image: image, mediaURL: nil)
    }

    /// Called after an editor export so the history reflects the new file.
    func registerExport(url: URL, image: CGImage, capturedAt: Date) {
        library.record(url: url, kind: .image, pixelSize: CGSize(width: image.width, height: image.height),
                       capturedAt: capturedAt, image: image)
    }

    func recordInLibrary(_ capture: PendingCapture) {
        guard let url = capture.savedURL else { return }
        library.record(url: url,
                       kind: .image,
                       pixelSize: capture.result.pixelSize,
                       capturedAt: capture.result.capturedAt,
                       image: capture.result.image)
    }

    func clearLibrary() {
        library.clearAll()
    }

    func editClipboardImage() {
        guard let image = Clipboard.image() else {
            ErrorPresenter.present(.unsupportedImageData)
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let result = CaptureResult(image: image, scale: scale, source: .clipboard)
        editorPresenter.present(result, savedURL: nil)
    }

    func copyTextOnScreen() async {
        guard let result = await captureCoordinator.selectAreaForRecognition() else { return }
        await textRecognitionPresenter.copyText(from: result.image)
    }

    func toggleRecording() {
        recordingPresenter.toggle()
    }
}
