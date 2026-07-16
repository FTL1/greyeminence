import Foundation
import SwiftData

/// How far a captured frame has progressed through the analysis pipeline.
/// Stored as a raw string on the model (SwiftData-friendly, forward-compatible).
enum FrameAnalysisState: String, Codable, Sendable {
    /// On-device OCR only — vision analysis disabled, unconfigured, or not yet attempted.
    case ocrOnly
    /// Queued for a Claude vision batch.
    case pendingVision
    /// Claude produced an observation.
    case analyzed
    /// Vision call failed terminally; OCR text remains usable.
    case failed
    /// Dropped from analysis by the per-meeting budget or batch overflow.
    case skipped
}

/// What kind of content Claude judged the frame to show. Constrained
/// vocabulary so the UI can badge frames and the analysis queue can reason
/// about them; `other` absorbs anything unrecognized.
enum FrameContentType: String, Codable, Sendable {
    case slide, code, diagram, dashboard, document, terminal, video, other
}

/// One kept screenshot of a shared-screen window during a recording.
/// Image bytes live on the file system (like audio); this row carries the
/// metadata, OCR text, and the AI observation.
@Model
final class ScreenShareFrame {
    var id: UUID
    /// Groups contiguous frames of one share (window appeared → disappeared).
    /// A re-share starts a new session.
    var sessionID: UUID
    /// Ordinal within the session.
    var sequence: Int
    /// Elapsed seconds since recording start — the same clock as
    /// `TranscriptSegment.startTime`, so frames and speech align directly.
    var timestamp: TimeInterval
    /// Wall-clock capture moment, for interrupted-recording forensics.
    var capturedAt: Date
    /// Path relative to the meeting's recording directory,
    /// e.g. "frames/1a2b3c4d/000042.jpg".
    var imagePath: String
    var windowTitle: String?
    var ocrText: String?
    /// dHash of the frame, stored as the bit pattern (UInt64 → Int64).
    var dedupeHash: Int64
    /// True when the hash changed but the OCR text stayed ~identical —
    /// typically video playback; the analysis queue deprioritizes these.
    var isVisualOnlyChange: Bool = false
    /// Claude's 1–2 sentence observation of what the frame shows.
    var observation: String?
    var contentTypeRaw: String?
    var keyEntities: [String] = []
    var analysisStateRaw: String
    /// Which model produced `observation`.
    var analysisModelIdentifier: String?
    var meeting: Meeting?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        sequence: Int,
        timestamp: TimeInterval,
        capturedAt: Date = .now,
        imagePath: String,
        windowTitle: String? = nil,
        ocrText: String? = nil,
        dedupeHash: Int64 = 0,
        isVisualOnlyChange: Bool = false,
        analysisState: FrameAnalysisState = .ocrOnly
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.capturedAt = capturedAt
        self.imagePath = imagePath
        self.windowTitle = windowTitle
        self.ocrText = ocrText
        self.dedupeHash = dedupeHash
        self.isVisualOnlyChange = isVisualOnlyChange
        self.analysisStateRaw = analysisState.rawValue
    }

    var analysisState: FrameAnalysisState {
        get { FrameAnalysisState(rawValue: analysisStateRaw) ?? .ocrOnly }
        set { analysisStateRaw = newValue.rawValue }
    }

    var contentType: FrameContentType? {
        get { contentTypeRaw.flatMap(FrameContentType.init(rawValue:)) }
        set { contentTypeRaw = newValue?.rawValue }
    }

    /// "m:ss" render of `timestamp`, matching `TranscriptSegment.formattedTimestamp`.
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A contiguous share session derived from frames at read time — sessions
/// carry no independent mutable state, so they are not modeled separately.
struct ShareSession: Sendable, Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let windowTitle: String?
    let frameCount: Int

    /// Group frames by `sessionID`, ordered by start time.
    static func sessions(from frames: [ScreenShareFrame]) -> [ShareSession] {
        var bySession: [UUID: [ScreenShareFrame]] = [:]
        for frame in frames {
            bySession[frame.sessionID, default: []].append(frame)
        }
        return bySession.map { id, frames in
            ShareSession(
                id: id,
                startTime: frames.map(\.timestamp).min() ?? 0,
                endTime: frames.map(\.timestamp).max() ?? 0,
                windowTitle: frames.first?.windowTitle,
                frameCount: frames.count
            )
        }
        .sorted { $0.startTime < $1.startTime }
    }
}
