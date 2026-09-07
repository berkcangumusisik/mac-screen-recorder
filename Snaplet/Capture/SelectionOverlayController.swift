import AppKit

/// A borderless, shielding-level window that can take keyboard focus so Esc
/// cancels the selection.
final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Presents the selection overlay across every connected display and resolves
/// to exactly one outcome.
///
/// The overlay draws a snapshot taken *before* it appeared, so Snaplet's own
/// chrome can never end up in the result.
@MainActor
final class SelectionOverlayController {

    enum Mode {
        case area
        case window
    }

    enum Outcome {
        /// `rect` is in global AppKit points and is guaranteed to be inside `snapshot.frame`.
        case area(snapshot: DisplaySnapshot, rect: CGRect)
        case window(WindowCandidate)
        case cancelled
    }

    private var windows: [SelectionOverlayWindow] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var previousApplication: NSRunningApplication?
    private var screenChangeObserver: NSObjectProtocol?

    var isPresenting: Bool { !windows.isEmpty }

    func present(mode: Mode,
                 snapshots: [DisplaySnapshot],
                 candidates: [WindowCandidate]) async -> Outcome {
        guard !isPresenting else { return .cancelled }
        guard !snapshots.isEmpty else { return .cancelled }

        previousApplication = NSWorkspace.shared.frontmostApplication

        for snapshot in snapshots {
            let view = SelectionOverlayView(snapshot: snapshot, mode: mode)
            view.controller = self
            view.candidates = candidates.filter { $0.appKitFrame.intersects(snapshot.frame) }

            let window = SelectionOverlayWindow(contentRect: snapshot.frame,
                                                styleMask: [.borderless],
                                                backing: .buffered,
                                                defer: false)
            window.contentView = view
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.setFrame(snapshot.frame, display: false)
            window.orderFrontRegardless()

            windows.append(window)
            views.append(view)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        if let view = views.first { windows.first?.makeFirstResponder(view) }

        // A display being plugged or unplugged invalidates every snapshot.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    func viewDidSelectArea(_ rect: CGRect, in view: SelectionOverlayView) {
        let global = CGRect(x: view.snapshot.frame.minX + rect.minX,
                            y: view.snapshot.frame.minY + rect.minY,
                            width: rect.width,
                            height: rect.height)
        finish(.area(snapshot: view.snapshot, rect: global))
    }

    func viewDidSelectWindow(_ candidate: WindowCandidate) {
        finish(.window(candidate))
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil

        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        views.removeAll()

        // Give focus back to whatever the user was actually working in.
        if let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil

        continuation.resume(returning: outcome)
    }
}
