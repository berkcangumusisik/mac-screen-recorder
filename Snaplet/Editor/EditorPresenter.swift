import AppKit

/// Opens and tracks editor windows. One window per document; closing the last
/// one releases every backing image.
@MainActor
final class EditorPresenter {

    private unowned let environment: AppEnvironment
    private var controllers: [ObjectIdentifier: EditorWindowController] = [:]

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func present(_ result: CaptureResult, savedURL: URL?) {
        let document = EditorDocument(image: result.image,
                                      scale: result.scale,
                                      sourceURL: savedURL,
                                      capturedAt: result.capturedAt)
        present(document: document)
    }

    func present(document: EditorDocument) {
        let controller = EditorWindowController(document: document, environment: environment)
        controllers[ObjectIdentifier(controller)] = controller
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeValue(forKey: ObjectIdentifier(controller))
        }
        controller.show()
    }
}
