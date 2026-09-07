import AppKit
import SwiftUI

/// Full-screen countdown shown before recording starts.
@MainActor
final class CountdownOverlay {

    private var windows: [NSWindow] = []
    private let model = CountdownModel()

    func show(seconds: Int) {
        hide()
        model.remaining = seconds
        for screen in NSScreen.screens {
            let hosting = NSHostingView(rootView: CountdownView(model: model))
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false)
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func update(remaining: Int) {
        model.remaining = remaining
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining: Int = 3
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
            Text("\(model.remaining)")
                .font(.system(size: 160, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 24)
                .padding(60)
                .background(.ultraThinMaterial, in: Circle())
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
