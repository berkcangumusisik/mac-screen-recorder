import AVFoundation
import CoreImage

enum VideoCompositionBuilder {

    /// Builds the Core Image composition used by both the preview player and
    /// the exporter, so the two can never disagree.
    static func make(asset: AVAsset,
                     edit: VideoEdit,
                     sourceSize: CGSize,
                     frameRate: Int) async throws -> (composition: AVMutableVideoComposition, renderSize: CGSize) {
        let renderer = VideoFrameRenderer(edit: edit, sourceSize: sourceSize)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let output = renderer.render(request.sourceImage, at: request.compositionTime.seconds)
            request.finish(with: output, context: nil)
        }
        composition.renderSize = renderer.canvasSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        return (composition, renderer.canvasSize)
    }

    /// Natural display size of the first video track, with its preferred
    /// transform applied.
    static func displaySize(of asset: AVAsset) async throws -> CGSize {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw SnapletError.exportFailed("the file has no video track")
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    static func nominalFrameRate(of asset: AVAsset) async -> Int {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.nominalFrameRate), rate > 1 else { return 30 }
        return Int(rate.rounded())
    }
}
