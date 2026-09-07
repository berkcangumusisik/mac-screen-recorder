import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A full-display image captured immediately before the selection overlay is
/// shown. Selection then crops this image, which means the overlay itself can
/// never appear in the output and the capture is instantaneous.
struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    /// Display bounds in global AppKit points.
    let frame: CGRect
    /// Backing scale factor (pixels per point).
    let scale: CGFloat
    let image: CGImage

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

/// What the user picked, expressed so it can be replayed later.
enum CaptureSource: Equatable {
    case area(displayID: CGDirectDisplayID, rect: CGRect)
    case window(windowID: CGWindowID, title: String?)
    case fullScreen(displayID: CGDirectDisplayID)
    case clipboard
    case importedFile(URL)
}

/// The product of a still capture.
struct CaptureResult {
    let image: CGImage
    /// Pixels per point of the captured image.
    let scale: CGFloat
    let source: CaptureSource
    let capturedAt: Date

    init(image: CGImage, scale: CGFloat, source: CaptureSource, capturedAt: Date = Date()) {
        self.image = image
        self.scale = scale
        self.source = source
        self.capturedAt = capturedAt
    }

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
    var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

/// A window the user can pick during window capture.
struct WindowCandidate {
    let scWindow: SCWindow
    /// Window bounds converted to global AppKit points.
    let appKitFrame: CGRect
    let applicationName: String
    let title: String?
}
