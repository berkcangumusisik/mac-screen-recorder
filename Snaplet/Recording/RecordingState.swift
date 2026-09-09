import Foundation

/// Explicit recording lifecycle. Every transition is checked, so a second
/// hot-key press or a stray delegate callback cannot corrupt a session.
enum RecordingState: Equatable {
    case idle
    case preparing
    case countingDown(remaining: Int)
    case recording(startedAt: Date)
    case paused(since: Date)
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

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// Pausing only makes sense once frames are actually being written.
    var canPause: Bool { isRecording }

    /// Whether the user pressing the toggle should stop rather than start.
    var respondsToStop: Bool {
        switch self {
        case .countingDown, .recording, .paused: return true
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
             (.recording, .paused),
             (.paused, .recording),
             (.paused, .stopping),
             (.stopping, .finalizing),
             (.finalizing, .idle),
             (.idle, .idle),
             // Abandoning before anything was captured: the user cancelled the
             // area or window picker, cancelled the countdown, or setup gave up.
             // Without these the presenter would be stuck outside .idle and
             // every later start request would be silently ignored.
             (.preparing, .idle),
             (.countingDown, .idle),
             (.stopping, .idle):
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
