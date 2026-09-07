import AppKit

@MainActor
final class VideoEditorPresenter {
    private unowned let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    func present(url: URL) {}
}
