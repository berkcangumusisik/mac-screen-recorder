import Foundation

/// Explicit recording lifecycle. Every transition is checked, so a second
/// hot-key press or a stray delegate callback cannot corrupt a session.
enum RecordingState: Equatable {
    case idle
    case preparing
    case countingDown(remaining: Int)
    case recording(startedAt: Date)
    case stopping
    case finalizing
    case failed(SnapletError)

    var isActive: Bool {
        switch self {
        case .idle, .failed: return false
        default: return true
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Whether the user pressing the toggle should stop rather than start.
    var respondsToStop: Bool {
        switch self {
        case .countingDown, .recording: return true
        default: return false
        }
    }

    func canTransition(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.idle, .preparing),
             (.preparing, .countingDown),
             (.preparing, .recording),
             (.countingDown, .countingDown),
             (.countingDown, .recording),
             (.countingDown, .stopping),
             (.recording, .stopping),
             (.stopping, .finalizing),
             (.finalizing, .idle),
             (.idle, .idle):
            return true
        case (_, .failed):
            return true
        case (.failed, .idle), (.failed, .preparing):
            return true
        default:
            return false
        }
    }
}
