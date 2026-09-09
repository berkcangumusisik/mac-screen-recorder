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
        /// The composed selection. `rect` is in global AppKit points and may
        /// cross displays, in which case the image is stitched from each one.
        case area(image: CGImage, scale: CGFloat, rect: CGRect, displayID: CGDirectDisplayID)
        case window(WindowCandidate)
        case cancelled
    }

    private var windows: [SelectionOverlayWindow] = []
    private var views: [SelectionOverlayView] = []
    private var snapshots: [DisplaySnapshot] = []

    // The drag lives here, in global coordinates, rather than in whichever view
    // the mouse went down on — that is what lets a selection cross displays.
    private var dragAnchor: CGPoint?
    private var dragCurrent: CGPoint?
    private var isMovingSelection = false
    private var moveOrigin: CGPoint?
    private var movedRectAtStart: CGRect?
    /// The display the drag started on, used to replay the selection later.
    private var originDisplayID: CGDirectDisplayID?
    /// Set for flows that cannot span displays, such as choosing a recording area.
    var confinesSelectionToOneDisplay = false
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var previousApplication: NSRunningApplication?
    private var screenChangeObserver: NSObjectProtocol?

    var isPresenting: Bool { !windows.isEmpty }

    func present(mode: Mode,
                 snapshots: [DisplaySnapshot],
                 candidates: [WindowCandidate]) async -> Outcome {
        guard !isPresenting else { return .cancelled }
        guard !snapshots.isEmpty else { return .cancelled }

        self.snapshots = snapshots
        dragAnchor = nil
        dragCurrent = nil
        isMovingSelection = false
        originDisplayID = nil
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

    // MARK: - Dragging, in global coordinates

    func beginDrag(at global: CGPoint) {
        dragAnchor = global
        dragCurrent = global
        isMovingSelection = false
        originDisplayID = snapshots.first { $0.frame.contains(global) }?.displayID
        refreshViews()
    }

    func updateDrag(to global: CGPoint) {
        guard dragAnchor != nil else { return }
        if isMovingSelection, let moveOrigin, let movedRectAtStart {
            let moved = movedRectAtStart.offsetBy(dx: global.x - moveOrigin.x,
                                                  dy: global.y - moveOrigin.y)
            dragAnchor = CGPoint(x: moved.minX, y: moved.minY)
            dragCurrent = CGPoint(x: moved.maxX, y: moved.maxY)
        } else {
            dragCurrent = global
        }
        refreshViews()
    }

    func beginMovingSelection(from global: CGPoint) {
        guard dragAnchor != nil, let rect = globalSelection else { return }
        isMovingSelection = true
        moveOrigin = global
        movedRectAtStart = rect
    }

    func endMovingSelection() {
        isMovingSelection = false
        moveOrigin = nil
        movedRectAtStart = nil
    }

    func endDrag() {
        defer {
            dragAnchor = nil
            dragCurrent = nil
            endMovingSelection()
        }
        guard let rect = globalSelection, rect.width >= 2, rect.height >= 2 else {
            refreshViews()
            return
        }
        guard let composed = MultiDisplayCompositor.composite(selection: rect, from: snapshots) else {
            refreshViews()
            return
        }
        let displayID = originDisplayID
            ?? snapshots.first { $0.frame.intersects(rect) }?.displayID
            ?? 0
        finish(.area(image: composed.image, scale: composed.scale, rect: rect, displayID: displayID))
    }

    /// The selection in global points, with the live modifier keys applied.
    var globalSelection: CGRect? {
        guard let dragAnchor, let dragCurrent else { return nil }
        var rect = ScreenGeometry.rect(from: dragAnchor, to: dragCurrent)

        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            let side = max(rect.width, rect.height)
            let signX: CGFloat = dragCurrent.x >= dragAnchor.x ? 1 : -1
            let signY: CGFloat = dragCurrent.y >= dragAnchor.y ? 1 : -1
            rect = ScreenGeometry.rect(from: dragAnchor,
                                       to: CGPoint(x: dragAnchor.x + side * signX,
                                                   y: dragAnchor.y + side * signY))
        }
        if flags.contains(.option) {
            rect = CGRect(x: dragAnchor.x - rect.width,
                          y: dragAnchor.y - rect.height,
                          width: rect.width * 2,
                          height: rect.height * 2)
        }

        if confinesSelectionToOneDisplay,
           let origin = originDisplayID,
           let display = snapshots.first(where: { $0.displayID == origin }) {
            rect = rect.intersection(display.frame)
        }
        return rect.isNull ? nil : rect
    }

    private func refreshViews() {
        for view in views { view.refreshFromController() }
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
        snapshots.removeAll()
        dragAnchor = nil
        dragCurrent = nil
        endMovingSelection()

        // Give focus back to whatever the user was actually working in.
        if let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil

        continuation.resume(returning: outcome)
    }
}
