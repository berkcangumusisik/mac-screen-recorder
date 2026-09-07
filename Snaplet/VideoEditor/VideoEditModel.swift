import CoreGraphics
import Foundation

/// A time-ranged overlay drawn into the video.
///
/// `frame` is normalised to the source video (0…1, top-left origin) so an edit
/// stays correct whatever resolution the export uses.
struct VideoOverlay: Identifiable, Equatable, Sendable {

    enum Kind: String, Codable, CaseIterable, Sendable {
        case text
        case redaction

        var displayName: String {
            self == .text ? String(localized: "Text") : String(localized: "Redaction")
        }
    }

    var id = UUID()
    var kind: Kind
    var start: Double
    var end: Double
    var frame: CGRect
    var text: String = ""
    /// Font size as a fraction of the video height.
    var fontFraction: Double = 0.06
    var color: RGBAColor = .white
    var backgroundColor: RGBAColor = RGBAColor(red: 0.06, green: 0.06, blue: 0.07)

    func isVisible(at time: Double) -> Bool {
        time >= start && time <= end
    }
}

/// A "look closer" emphasis: the frame eases into a region and back out.
struct ZoomEmphasis: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    /// Region to zoom into, normalised to the source video (top-left origin).
    var focus: CGRect
    /// Seconds spent easing in and easing out.
    var ramp: Double = 0.45

    /// 0 at the edges of the range, 1 while fully zoomed.
    func intensity(at time: Double) -> Double {
        guard time >= start, time <= end else { return 0 }
        let ramp = max(0.01, min(self.ramp, (end - start) / 2))
        let easeIn = min(1, (time - start) / ramp)
        let easeOut = min(1, (end - time) / ramp)
        let linear = max(0, min(1, min(easeIn, easeOut)))
        // Smoothstep, so the movement starts and stops gently.
        return linear * linear * (3 - 2 * linear)
    }

    /// The magnification applied when fully zoomed in.
    var maximumScale: CGFloat {
        let width = max(0.05, focus.width)
        let height = max(0.05, focus.height)
        return 1 / max(width, height)
    }

    /// Transform applied to a video frame of `size`.
    ///
    /// Pass `flipY: true` for Core Image, whose origin is bottom-left; the
    /// stored focus rectangle uses the top-left convention used everywhere else
    /// in Snaplet.
    func transform(at time: Double, videoSize: CGSize, flipY: Bool = false) -> CGAffineTransform {
        let intensity = intensity(at: time)
        guard intensity > 0.0001 else { return .identity }
        let scale = 1 + (maximumScale - 1) * CGFloat(intensity)

        let focusMidY = flipY ? (1 - focus.midY) : focus.midY
        let focusCenter = CGPoint(x: (focus.midX) * videoSize.width,
                                  y: focusMidY * videoSize.height)
        let frameCenter = CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)
        let center = CGPoint(x: frameCenter.x + (focusCenter.x - frameCenter.x) * CGFloat(intensity),
                             y: frameCenter.y + (focusCenter.y - frameCenter.y) * CGFloat(intensity))

        return CGAffineTransform.identity
            .translatedBy(x: frameCenter.x, y: frameCenter.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
    }
}

/// Everything the video editor can change. Preview and export both read this,
/// which is what keeps them identical.
struct VideoEdit: Equatable, Sendable {
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var overlays: [VideoOverlay] = []
    var zooms: [ZoomEmphasis] = []
    var style: StylePreset?
    var resolutionCap: ResolutionCap = .original

    var trimmedDuration: Double { max(0, trimEnd - trimStart) }

    /// Output pixel size for a source of `sourceSize`, never upscaled.
    func outputSize(forSource sourceSize: CGSize) -> CGSize {
        var width = sourceSize.width
        var height = sourceSize.height
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

    /// Final canvas size once presentation styling is applied.
    func canvasSize(forSource sourceSize: CGSize) -> CGSize {
        let content = outputSize(forSource: sourceSize)
        guard let style else { return content }
        let layout = PresentationRenderer.layout(contentSize: content, style: style)
        return CGSize(width: max(2, (layout.canvasSize.width / 2).rounded() * 2),
                      height: max(2, (layout.canvasSize.height / 2).rounded() * 2))
    }

    /// Where the video content sits inside the styled canvas, normalised to the
    /// canvas with a top-left origin. Used to map overlay coordinates onto the
    /// preview, which shows the composed canvas rather than the raw frame.
    func contentRectInCanvas(sourceSize: CGSize) -> CGRect {
        let content = outputSize(forSource: sourceSize)
        guard let style else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let layout = PresentationRenderer.layout(contentSize: content, style: style)
        guard layout.canvasSize.width > 0, layout.canvasSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: layout.contentRect.minX / layout.canvasSize.width,
                      y: layout.contentRect.minY / layout.canvasSize.height,
                      width: layout.contentRect.width / layout.canvasSize.width,
                      height: layout.contentRect.height / layout.canvasSize.height)
    }

    func overlays(at time: Double) -> [VideoOverlay] {
        overlays.filter { $0.isVisible(at: time) }
    }
}

/// GIF limits, enforced rather than merely suggested.
struct GIFExportOptions: Equatable, Sendable {
    var frameRate: Int = 12
    var maximumWidth: Int = 640
    /// Hard cap on the exported clip length.
    static let maximumDuration: Double = 30

    static func clampedRange(start: Double, end: Double) -> (start: Double, end: Double) {
        let clampedEnd = min(end, start + maximumDuration)
        return (start, max(start + 0.1, clampedEnd))
    }
}
