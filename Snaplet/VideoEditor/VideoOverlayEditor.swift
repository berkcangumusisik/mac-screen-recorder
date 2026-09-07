import SwiftUI

/// Interactive layer over the preview for placing and moving overlays.
///
/// Rectangles are stored normalised to the *source* video; this view maps them
/// through the styled canvas so what you drag is where it lands.
struct VideoOverlayEditor: View {

    @ObservedObject var document: VideoDocument
    /// The tool the next drag creates, or `nil` for plain selection.
    @Binding var placementKind: PlacementKind?

    enum PlacementKind: String, Identifiable {
        case text, redaction, zoom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return String(localized: "Add text")
            case .redaction: return String(localized: "Add redaction")
            case .zoom: return String(localized: "Add zoom")
            }
        }
        var symbol: String {
            switch self {
            case .text: return "textformat"
            case .redaction: return "rectangle.fill"
            case .zoom: return "plus.magnifyingglass"
            }
        }
    }

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let videoRect = displayedVideoRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture(videoRect: videoRect))

                ForEach(document.edit.overlays) { overlay in
                    if overlay.isVisible(at: document.currentTime) {
                        rectangle(for: overlay.frame, in: videoRect,
                                  color: overlay.kind == .redaction ? .orange : .blue,
                                  isSelected: overlay.id == document.selectedOverlayID)
                            .onTapGesture {
                                document.selectedOverlayID = overlay.id
                                document.selectedZoomID = nil
                            }
                    }
                }

                ForEach(document.edit.zooms) { zoom in
                    if zoom.intensity(at: document.currentTime) > 0 || zoom.id == document.selectedZoomID {
                        rectangle(for: zoom.focus, in: videoRect, color: .green,
                                  isSelected: zoom.id == document.selectedZoomID)
                            .onTapGesture {
                                document.selectedZoomID = zoom.id
                                document.selectedOverlayID = nil
                            }
                    }
                }

                if let start = dragStart, let current = dragCurrent {
                    let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                                      width: abs(start.x - current.x), height: abs(start.y - current.y))
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Geometry

    /// The composed canvas as it appears inside the preview, aspect-fitted.
    private func displayedVideoRect(in size: CGSize) -> CGRect {
        let canvas = document.edit.canvasSize(forSource: document.sourceSize)
        guard canvas.width > 0, canvas.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        let displayed = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        return CGRect(x: (size.width - displayed.width) / 2,
                      y: (size.height - displayed.height) / 2,
                      width: displayed.width,
                      height: displayed.height)
    }

    /// source-normalised -> view points
    private func viewRect(for normalised: CGRect, in videoRect: CGRect) -> CGRect {
        let content = document.edit.contentRectInCanvas(sourceSize: document.sourceSize)
        let x = videoRect.minX + (content.minX + normalised.minX * content.width) * videoRect.width
        let y = videoRect.minY + (content.minY + normalised.minY * content.height) * videoRect.height
        return CGRect(x: x,
                      y: y,
                      width: normalised.width * content.width * videoRect.width,
                      height: normalised.height * content.height * videoRect.height)
    }

    /// view points -> source-normalised
    private func normalisedRect(from rect: CGRect, in videoRect: CGRect) -> CGRect {
        let content = document.edit.contentRectInCanvas(sourceSize: document.sourceSize)
        guard videoRect.width > 0, videoRect.height > 0,
              content.width > 0, content.height > 0 else { return .zero }
        let x = ((rect.minX - videoRect.minX) / videoRect.width - content.minX) / content.width
        let y = ((rect.minY - videoRect.minY) / videoRect.height - content.minY) / content.height
        let width = rect.width / videoRect.width / content.width
        let height = rect.height / videoRect.height / content.height
        return CGRect(x: min(max(0, x), 1),
                      y: min(max(0, y), 1),
                      width: min(width, 1),
                      height: min(height, 1))
    }

    // MARK: - Pieces

    private func rectangle(for normalised: CGRect,
                           in videoRect: CGRect,
                           color: Color,
                           isSelected: Bool) -> some View {
        let rect = viewRect(for: normalised, in: videoRect)
        return Rectangle()
            .strokeBorder(color, style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5,
                                                    dash: isSelected ? [] : [4, 3]))
            .background(color.opacity(isSelected ? 0.12 : 0.06))
            .frame(width: max(2, rect.width), height: max(2, rect.height))
            .offset(x: rect.minX, y: rect.minY)
    }

    private func dragGesture(videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard let start = dragStart else { return }
                let rect = CGRect(x: min(start.x, value.location.x),
                                  y: min(start.y, value.location.y),
                                  width: abs(start.x - value.location.x),
                                  height: abs(start.y - value.location.y))
                guard rect.width > 8, rect.height > 8 else { return }
                let normalised = normalisedRect(from: rect, in: videoRect)
                guard normalised.width > 0.01, normalised.height > 0.01 else { return }

                switch placementKind {
                case .text:
                    document.addOverlay(kind: .text, frame: normalised)
                case .redaction:
                    document.addOverlay(kind: .redaction, frame: normalised)
                case .zoom:
                    document.addZoom(focus: normalised)
                case .none:
                    return
                }
                placementKind = nil
            }
    }
}
