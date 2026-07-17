import Foundation
import SwiftData

/// One share session's synthesized narrative: what was shown, fused with
/// what was said while it was on screen. Written once per session by
/// `ShareSessionSynthesisService`; the final meeting analysis receives these
/// instead of raw per-frame bullets.
@Model
final class ShareSessionSummary {
    /// The `ScreenShareFrame.sessionID` this summarizes. Unique — synthesis
    /// can be triggered from more than one path (60s loop, stop sweep,
    /// player backfill) and the constraint is the exactly-once backstop.
    @Attribute(.unique) var sessionID: UUID
    var windowTitle: String?
    /// Session bounds in elapsed seconds — same clock as frame timestamps.
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// One 120–250 word paragraph grounding what was shown against what was
    /// said around the session.
    var narrative: String
    /// JSON-encoded [KeyMoment] — kept as a string so the schema stays flat.
    var keyMomentsJSON: String
    var entities: [String] = []
    /// Which model produced the narrative.
    var modelIdentifier: String?
    var createdAt: Date
    var meeting: Meeting?

    init(
        sessionID: UUID,
        windowTitle: String? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        narrative: String,
        keyMoments: [KeyMoment] = [],
        entities: [String] = [],
        modelIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.sessionID = sessionID
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.endTime = endTime
        self.narrative = narrative
        self.keyMomentsJSON = Self.encode(keyMoments)
        self.entities = entities
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
    }

    struct KeyMoment: Codable, Sendable, Equatable {
        /// Elapsed seconds since recording start.
        var timestamp: TimeInterval
        var label: String
    }

    var keyMoments: [KeyMoment] {
        get {
            guard let data = keyMomentsJSON.data(using: .utf8),
                  let moments = try? JSONDecoder().decode([KeyMoment].self, from: data) else {
                return []
            }
            return moments
        }
        set { keyMomentsJSON = Self.encode(newValue) }
    }

    private static func encode(_ moments: [KeyMoment]) -> String {
        guard let data = try? JSONEncoder().encode(moments),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}
