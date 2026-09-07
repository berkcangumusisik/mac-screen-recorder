import Foundation

struct SensitiveSuggestion: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: SensitiveDataDetector.Kind
    let text: String
    /// Normalised to the image, top-left origin.
    let boundingBox: CGRect
}

/// Looks for text that often should not be in a shared screenshot.
///
/// This is a helpful hint, not a guarantee: it works only on text Vision could
/// read, it uses shape-based patterns, and it will both miss things and flag
/// harmless ones. Nothing is hidden until the user says so.
enum SensitiveDataDetector {

    enum Kind: String, Sendable, CaseIterable {
        case email
        case apiKey
        case bearerToken
        case jwt
        case ipAddress
        case longNumber

        var displayName: String {
            switch self {
            case .email: return String(localized: "Email address")
            case .apiKey: return String(localized: "Key-like string")
            case .bearerToken: return String(localized: "Authorisation header")
            case .jwt: return String(localized: "Token")
            case .ipAddress: return String(localized: "IP address")
            case .longNumber: return String(localized: "Long number")
            }
        }
    }

    struct Match: Equatable {
        let kind: Kind
        let range: Range<String.Index>
    }

    private static let patterns: [(Kind, String)] = [
        (.email, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        (.jwt, #"eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}"#),
        (.bearerToken, #"(?:Bearer|Basic|Token)\s+[A-Za-z0-9._\-/+=]{12,}"#),
        (.apiKey, #"\b(?:sk|pk|rk|api|key|ghp|gho|AKIA|ASIA)[-_A-Za-z0-9]{12,}\b"#),
        (.ipAddress, #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
        (.longNumber, #"\b\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{2,7}\b"#)
    ]

    private static let expressions: [(Kind, NSRegularExpression)] = patterns.compactMap { kind, pattern in
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return (kind, expression)
    }

    static func matches(in string: String) -> [Match] {
        guard !string.isEmpty else { return [] }
        let full = NSRange(string.startIndex..<string.endIndex, in: string)
        var results: [Match] = []

        for (kind, expression) in expressions {
            for match in expression.matches(in: string, options: [], range: full) {
                guard let range = Range(match.range, in: string) else { continue }
                // Keep the first, most specific match for any overlapping span.
                let overlaps = results.contains { $0.range.overlaps(range) }
                if !overlaps {
                    results.append(Match(kind: kind, range: range))
                }
            }
        }
        return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
