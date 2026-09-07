import Foundation
import OSLog

/// Lightweight, opt-out-free-of-network timing used to keep the performance
/// claims in the documentation honest. Samples live only in memory for the
/// current run and are never written to disk or sent anywhere.
@MainActor
final class Metrics {
    static let shared = Metrics()

    struct Sample: Identifiable {
        let id = UUID()
        let name: String
        let duration: TimeInterval
        let date: Date
    }

    private(set) var samples: [Sample] = []
    private let signposter = OSSignposter(subsystem: "app.snaplet.Snaplet", category: "performance")

    private init() {}

    func record(_ name: String, duration: TimeInterval) {
        samples.append(Sample(name: name, duration: duration, date: Date()))
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
        Log.app.debug("metric \(name, privacy: .public) \(Int(duration * 1000))ms")
    }

    /// Measures an async operation and records the elapsed wall-clock time.
    func measure<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval("measure", id: signposter.makeSignpostID())
        let start = ContinuousClock.now
        defer {
            signposter.endInterval("measure", state)
            record(name, duration: Double(start.duration(to: .now).components.attoseconds) / 1e18
                   + Double(start.duration(to: .now).components.seconds))
        }
        return try await body()
    }

    func summary(for name: String) -> (count: Int, medianMilliseconds: Double, p90Milliseconds: Double)? {
        let matching = samples.filter { $0.name == name }.map { $0.duration * 1000 }.sorted()
        guard !matching.isEmpty else { return nil }
        func percentile(_ p: Double) -> Double {
            let index = min(matching.count - 1, max(0, Int((Double(matching.count - 1) * p).rounded())))
            return matching[index]
        }
        return (matching.count, percentile(0.5), percentile(0.9))
    }

    /// Plain-text report the user can copy from the Help window.
    func report() -> String {
        let names = Array(Set(samples.map(\.name))).sorted()
        guard !names.isEmpty else {
            return String(localized: "No measurements recorded in this session yet.")
        }
        var lines = ["Snaplet performance (this session, wall clock)"]
        for name in names {
            guard let summary = summary(for: name) else { continue }
            lines.append(String(format: "%@  n=%d  median %.0f ms  p90 %.0f ms",
                                name, summary.count, summary.medianMilliseconds, summary.p90Milliseconds))
        }
        return lines.joined(separator: "\n")
    }

    func reset() { samples.removeAll() }
}

/// Names are stable so they can be referenced from documentation.
enum MetricName {
    static let shortcutToOverlay = "shortcut→overlay"
    static let selectionToClipboard = "selection→clipboard"
    static let windowCapture = "window capture"
    static let fullScreenCapture = "full screen capture"
    static let imageExport = "image export"
    static let videoExport = "video export"
    static let ocrPass = "ocr pass"
}
