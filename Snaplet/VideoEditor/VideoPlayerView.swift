import AVFoundation
import AppKit
import SwiftUI

/// Hosts an `AVPlayerLayer`. SwiftUI's `VideoPlayer` adds transport controls
/// Snaplet does not want on top of the editing surface.
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }

    final class PlayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(playerLayer)
            setAccessibilityLabel(String(localized: "Video preview"))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
