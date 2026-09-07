import AppKit

@MainActor
final class LibraryWindowController {
    private unowned let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    func show() {}
}
