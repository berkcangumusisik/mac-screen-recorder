import AppKit

/// Placeholder wiring for the recording stage. Replaced with the real state
/// machine in the recording commit.
@MainActor
final class RecordingPresenter {
    private unowned let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    var menuTitle: String { HotkeyAction.toggleRecording.title }
    func toggle() {}
}
