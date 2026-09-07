import AppKit
import CoreMedia
import ScreenCaptureKit

/// What to record and how.
struct RecordingConfiguration {

    enum Target {
        case display(CGDirectDisplayID)
        /// `rect` is in global AppKit points and must be inside the display.
        case area(displayID: CGDirectDisplayID, rect: CGRect)
        case window(CGWindowID)

        var displayID: CGDirectDisplayID? {
            switch self {
            case .display(let id), .area(let id, _): return id
            case .window: return nil
            }
        }
    }

    var target: Target
    var frameRate: Int = 60
    var resolutionCap: ResolutionCap = .original
    var capturesSystemAudio = true
    var capturesMicrophone = false
    var showsCursor = true
    var highlightsClicks = false
    var countdownSeconds = 3
    var webcam: WebcamOverlayConfiguration?

    /// Output pixel size for a source of `sourcePixelSize`, never upscaled and
    /// always even so H.264 encoders are happy.
    func outputSize(forSource sourcePixelSize: CGSize) -> CGSize {
        var width = sourcePixelSize.width
        var height = sourcePixelSize.height
        if let limit = resolutionCap.longestEdge {
            let longest = max(width, height)
            if longest > CGFloat(limit) {
                let factor = CGFloat(limit) / longest
                width *= factor
                height *= factor
            }
        }
        return CGSize(width: max(2, (width / 2).rounded() * 2),
                      height: max(2, (height / 2).rounded() * 2))
    }
}

struct WebcamOverlayConfiguration {
    var deviceID: String?
    var shape: WebcamShape = .circle
    var corner: OverlayCorner = .bottomTrailing
    /// Overlay height as a fraction of the video height.
    var sizeFraction: Double = 0.22

    /// Overlay rectangle in output pixel coordinates, top-left origin.
    func frame(inVideoSize size: CGSize) -> CGRect {
        let side = max(64, size.height * sizeFraction)
        let width = shape == .circle ? side : side * 1.35
        let margin = size.height * 0.035
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeading: x = margin; y = margin
        case .topTrailing: x = size.width - width - margin; y = margin
        case .bottomLeading: x = margin; y = size.height - side - margin
        case .bottomTrailing: x = size.width - width - margin; y = size.height - side - margin
        }
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: side.rounded())
    }
}
