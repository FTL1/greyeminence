import Foundation

/// Caps so a forgotten recording cannot run overnight and drain the API.
enum CaptureSafetyPolicy {
    /// Wall-clock recording limit. Auto-stop even if the meeting app still
    /// holds the mic (Discord sitting in a channel, Teams left open).
    static let maxRecordingSeconds: TimeInterval = 4 * 60 * 60
    /// Auto-started recordings with no speech for this long are assumed stale.
    static let idleSpeechStopSeconds: TimeInterval = 20 * 60

    static func shouldAutoStopRecording(
        elapsed: TimeInterval,
        autoDetected: Bool,
        secondsSinceSpeech: TimeInterval?
    ) -> StopReason? {
        if elapsed >= maxRecordingSeconds { return .maxDuration }
        if autoDetected, let gap = secondsSinceSpeech, gap >= idleSpeechStopSeconds {
            return .idleSpeech
        }
        return nil
    }

    /// Live AI follows the recording. It does not time out on its own while
    /// the meeting is still being captured.
    static func shouldStopLiveAI(liveEnabled: Bool) -> Bool {
        !liveEnabled
    }

    enum StopReason: Equatable {
        case maxDuration
        case idleSpeech
        case killSwitch

        var message: String {
            switch self {
            case .maxDuration:
                "Recording stopped automatically after 4 hours so it cannot run overnight."
            case .idleSpeech:
                "Auto-recording stopped — nobody spoke for 20 minutes."
            case .killSwitch:
                "Stopped recording, live AI, and auto-start."
            }
        }
    }
}
