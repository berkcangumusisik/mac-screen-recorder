import SwiftUI

/// Scrubber plus trim handles, with overlay and zoom spans drawn underneath.
struct VideoTimelineView: View {
    @ObservedObject var document: VideoDocument

    private let trackHeight: CGFloat = 34
    private let handleWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = max(0.001, document.duration)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: trackHeight)

                // Trimmed-away regions.
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: max(0, x(for: document.edit.trimStart, width: width)), height: trackHeight)
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: max(0, width - x(for: document.edit.trimEnd, width: width)), height: trackHeight)
                    .offset(x: x(for: document.edit.trimEnd, width: width))

                ForEach(document.edit.zooms) { zoom in
                    span(start: zoom.start, end: zoom.end, width: width, color: .green, row: 0)
                        .onTapGesture {
                            document.selectedZoomID = zoom.id
                            document.selectedOverlayID = nil
                        }
                }
                ForEach(document.edit.overlays) { overlay in
                    span(start: overlay.start, end: overlay.end, width: width,
                         color: overlay.kind == .redaction ? .orange : .blue, row: 1)
                        .onTapGesture {
                            document.selectedOverlayID = overlay.id
                            document.selectedZoomID = nil
                        }
                }

                trimHandle(at: document.edit.trimStart, width: width, isStart: true)
                trimHandle(at: document.edit.trimEnd, width: width, isStart: false)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: trackHeight + 16)
                    .offset(x: x(for: document.currentTime, width: width) - 1, y: -8)
                    .allowsHitTesting(false)
            }
            .frame(height: trackHeight + 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seconds = min(max(0, value.location.x / width * duration), duration)
                        document.seek(to: seconds)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Timeline"))
            .accessibilityValue(Text(TimeFormatting.timecode(document.currentTime)))
            .accessibilityAdjustableAction { direction in
                let step = 1.0
                document.seek(to: document.currentTime + (direction == .increment ? step : -step))
            }
        }
        .frame(height: trackHeight + 20)
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        guard document.duration > 0 else { return 0 }
        return CGFloat(seconds / document.duration) * width
    }

    private func span(start: Double, end: Double, width: CGFloat, color: Color, row: Int) -> some View {
        let minX = x(for: start, width: width)
        let maxX = x(for: end, width: width)
        return RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(0.55))
            .frame(width: max(3, maxX - minX), height: 9)
            .offset(x: minX, y: 6 + CGFloat(row) * 12)
    }

    private func trimHandle(at seconds: Double, width: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: trackHeight)
            .offset(x: x(for: seconds, width: width) - (isStart ? handleWidth : 0))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seconds = min(max(0, value.location.x / width * document.duration), document.duration)
                        if isStart {
                            document.edit.trimStart = min(seconds, document.edit.trimEnd - 0.2)
                        } else {
                            document.edit.trimEnd = max(seconds, document.edit.trimStart + 0.2)
                        }
                    }
            )
            .accessibilityLabel(Text(isStart ? "Trim start" : "Trim end"))
            .accessibilityValue(Text(TimeFormatting.timecode(seconds)))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.5 : -0.5
                if isStart {
                    document.edit.trimStart = min(max(0, document.edit.trimStart + step),
                                                  document.edit.trimEnd - 0.2)
                } else {
                    document.edit.trimEnd = max(min(document.duration, document.edit.trimEnd + step),
                                                document.edit.trimStart + 0.2)
                }
            }
    }
}
