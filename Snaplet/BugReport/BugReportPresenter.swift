import AppKit

@MainActor
final class BugReportPresenter {
    private unowned let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    func present(image: CGImage?, mediaURL: URL?) {}
}
