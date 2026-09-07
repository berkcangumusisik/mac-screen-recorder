import CoreGraphics
import Foundation
import Vision

/// One recognised line of text.
struct RecognizedLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    /// Normalised to the image with a top-left origin, matching the rest of Snaplet.
    let boundingBox: CGRect
    let confidence: Float
}

struct RecognizedTextResult: Sendable {
    let lines: [RecognizedLine]

    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    var isEmpty: Bool { lines.isEmpty }
}

/// Apple Vision text recognition. Everything runs on this Mac; there is no
/// network call, no API key and no remote service.
struct TextRecognitionService {

    /// Languages Vision is asked to consider. Snaplet ships English and Turkish
    /// interfaces, so both are requested by default.
    static let defaultLanguages = ["en-US", "tr-TR"]

    /// Recognition is CPU-heavy, so it always runs off the main thread.
    func recognize(in image: CGImage,
                   languages: [String] = TextRecognitionService.defaultLanguages) async throws -> RecognizedTextResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.performSynchronously(image: image, languages: languages)
        }.value
    }

    private static func performSynchronously(image: CGImage, languages: [String]) throws -> RecognizedTextResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw SnapletError.ocrFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let lines: [RecognizedLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text,
                                  boundingBox: Self.topLeftRect(from: observation.boundingBox),
                                  confidence: candidate.confidence)
        }
        // Vision returns observations in no guaranteed reading order.
        let sorted = lines.sorted { lhs, rhs in
            if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 0.015 {
                return lhs.boundingBox.minY < rhs.boundingBox.minY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return RecognizedTextResult(lines: sorted)
    }

    /// Finds precise boxes for the sensitive substrings inside each line.
    func sensitiveRegions(in image: CGImage,
                          languages: [String] = TextRecognitionService.defaultLanguages)
        async throws -> [SensitiveSuggestion] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw SnapletError.ocrFailed(error.localizedDescription)
            }

            var suggestions: [SensitiveSuggestion] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let string = candidate.string
                for match in SensitiveDataDetector.matches(in: string) {
                    // Prefer the exact substring box; fall back to the whole line.
                    var box = Self.topLeftRect(from: observation.boundingBox)
                    if let rectangle = try? candidate.boundingBox(for: match.range) {
                        box = Self.topLeftRect(from: rectangle.boundingBox)
                    }
                    suggestions.append(SensitiveSuggestion(kind: match.kind,
                                                           text: String(string[match.range]),
                                                           boundingBox: box))
                }
            }
            return suggestions
        }.value
    }

    /// Vision reports normalised rects with a bottom-left origin.
    private static func topLeftRect(from rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a normalised box to pixels in the source image.
    static func pixelRect(_ normalised: CGRect, imageSize: CGSize, padding: CGFloat = 0.006) -> CGRect {
        let padded = normalised.insetBy(dx: -padding, dy: -padding)
        return CGRect(x: max(0, padded.minX * imageSize.width),
                      y: max(0, padded.minY * imageSize.height),
                      width: min(imageSize.width, padded.width * imageSize.width),
                      height: min(imageSize.height, padded.height * imageSize.height)).integral
    }
}
