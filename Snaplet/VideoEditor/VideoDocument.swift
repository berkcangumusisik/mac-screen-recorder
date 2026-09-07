import AVFoundation
import AppKit
import Combine

/// One video being edited. Owns the player and keeps its composition in step
/// with the edit model.
@MainActor
final class VideoDocument: ObservableObject {

    let url: URL
    let asset: AVURLAsset
    let player = AVPlayer()

    @Published private(set) var duration: Double = 0
    @Published private(set) var sourceSize: CGSize = .zero
    @Published private(set) var frameRate: Int = 30
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: SnapletError?

    @Published var edit = VideoEdit()
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var selectedOverlayID: UUID?
    @Published var selectedZoomID: UUID?

    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var rebuildTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        self.url = url
        self.asset = AVURLAsset(url: url)

        // Rebuilding the composition is not free, so coalesce rapid changes.
        $edit
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleCompositionRebuild() }
            .store(in: &cancellables)
    }

    func load() async {
        do {
            let loadedDuration = try await asset.load(.duration).seconds
            guard loadedDuration.isFinite, loadedDuration > 0 else {
                throw SnapletError.exportFailed("the file has no playable duration")
            }
            sourceSize = try await VideoCompositionBuilder.displaySize(of: asset)
            frameRate = await VideoCompositionBuilder.nominalFrameRate(of: asset)
            duration = loadedDuration
            edit.trimStart = 0
            edit.trimEnd = loadedDuration

            let item = AVPlayerItem(asset: asset)
            playerItem = item
            player.replaceCurrentItem(with: item)
            installTimeObserver()
            isLoaded = true
            scheduleCompositionRebuild()
        } catch {
            loadError = (error as? SnapletError) ?? .exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= edit.trimEnd - 0.05 { seek(to: edit.trimStart) }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
    }

    private func installTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.currentTime = time.seconds
                    // Keep playback inside the trimmed range.
                    if self.isPlaying, time.seconds >= self.edit.trimEnd {
                        self.player.pause()
                        self.isPlaying = false
                        self.seek(to: self.edit.trimEnd)
                    }
                }
            }
    }

    // MARK: - Composition

    private func scheduleCompositionRebuild() {
        rebuildTask?.cancel()
        let snapshot = edit
        let size = sourceSize
        let rate = frameRate
        rebuildTask = Task { [weak self] in
            guard let self, size.width > 0 else { return }
            do {
                let built = try await VideoCompositionBuilder.make(asset: asset,
                                                                   edit: snapshot,
                                                                   sourceSize: size,
                                                                   frameRate: rate)
                guard !Task.isCancelled else { return }
                self.playerItem?.videoComposition = built.composition
            } catch {
                Log.editor.error("Preview composition failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Editing

    func addOverlay(kind: VideoOverlay.Kind, frame: CGRect) {
        let length = min(3.0, max(0.5, edit.trimmedDuration / 4))
        var overlay = VideoOverlay(kind: kind,
                                   start: currentTime,
                                   end: min(edit.trimEnd, currentTime + length),
                                   frame: frame)
        if kind == .text { overlay.text = String(localized: "Describe this step") }
        edit.overlays.append(overlay)
        selectedOverlayID = overlay.id
        selectedZoomID = nil
    }

    func addZoom(focus: CGRect) {
        let length = min(4.0, max(1.0, edit.trimmedDuration / 4))
        let zoom = ZoomEmphasis(start: currentTime,
                                end: min(edit.trimEnd, currentTime + length),
                                focus: focus)
        edit.zooms.append(zoom)
        selectedZoomID = zoom.id
        selectedOverlayID = nil
    }

    func deleteSelection() {
        if let id = selectedOverlayID {
            edit.overlays.removeAll { $0.id == id }
            selectedOverlayID = nil
        }
        if let id = selectedZoomID {
            edit.zooms.removeAll { $0.id == id }
            selectedZoomID = nil
        }
    }

    var selectedOverlay: VideoOverlay? {
        guard let selectedOverlayID else { return nil }
        return edit.overlays.first { $0.id == selectedOverlayID }
    }

    var selectedZoom: ZoomEmphasis? {
        guard let selectedZoomID else { return nil }
        return edit.zooms.first { $0.id == selectedZoomID }
    }

    func update(_ overlay: VideoOverlay) {
        guard let index = edit.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        edit.overlays[index] = overlay
    }

    func update(_ zoom: ZoomEmphasis) {
        guard let index = edit.zooms.firstIndex(where: { $0.id == zoom.id }) else { return }
        edit.zooms[index] = zoom
    }

    /// Renders the composed frame at `seconds` as a still image.
    func extractFrame(at seconds: Double) async -> CGImage? {
        do {
            let built = try await VideoCompositionBuilder.make(asset: asset,
                                                               edit: edit,
                                                               sourceSize: sourceSize,
                                                               frameRate: frameRate)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.videoComposition = built.composition
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return image
        } catch {
            Log.editor.error("Frame extraction failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}
