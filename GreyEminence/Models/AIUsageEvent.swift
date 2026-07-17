import Foundation
import SwiftData

/// Why an AI call was made — the ledger's grouping key. Raw strings are
/// stored on the model, so renames need a mapping.
enum AIUsagePurpose: String, Codable, Sendable, CaseIterable {
    case transcriptInitial
    case transcriptRolling
    case transcriptFinal
    case frameAnalysis
    case sessionSynthesis
    case reanalysis
    case ask
    case interview
    case prep
    case other

    var displayName: String {
        switch self {
        case .transcriptInitial: "Initial analysis"
        case .transcriptRolling: "Rolling analysis"
        case .transcriptFinal: "Final analysis"
        case .frameAnalysis: "Frame analysis"
        case .sessionSynthesis: "Session recaps"
        case .reanalysis: "Reanalysis"
        case .ask: "Ask"
        case .interview: "Interview"
        case .prep: "Meeting prep"
        case .other: "Other"
        }
    }

    var group: AIUsageGroup {
        switch self {
        case .transcriptInitial, .transcriptRolling: .transcript
        case .transcriptFinal, .reanalysis: .finalAnalysis
        case .frameAnalysis, .sessionSynthesis: .screenShare
        case .ask, .interview, .prep, .other: .other
        }
    }
}

/// User-facing rollup buckets for the usage ledger — the granularity people
/// actually reason about ("what do my screen shares cost?"), with the
/// per-purpose rows as detail underneath.
enum AIUsageGroup: String, CaseIterable, Sendable {
    /// Live passes while recording: initial + rolling analysis.
    case transcript
    /// The polish passes: final cleanup at stop, and any reanalysis.
    case finalAnalysis
    /// Frame vision + session recap synthesis.
    case screenShare
    case other

    var displayName: String {
        switch self {
        case .transcript: "Transcript processing"
        case .finalAnalysis: "Final analysis"
        case .screenShare: "Screen shares"
        case .other: "Everything else"
        }
    }
}

/// One AI API call's token usage. `meetingID` is a plain UUID, not a
/// relationship — the ledger is an audit trail and survives meeting deletion.
@Model
final class AIUsageEvent {
    var timestamp: Date
    var meetingID: UUID?
    var purposeRaw: String
    var modelIdentifier: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    init(
        timestamp: Date = .now,
        meetingID: UUID? = nil,
        purpose: AIUsagePurpose,
        modelIdentifier: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.timestamp = timestamp
        self.meetingID = meetingID
        self.purposeRaw = purpose.rawValue
        self.modelIdentifier = modelIdentifier
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    var purpose: AIUsagePurpose {
        AIUsagePurpose(rawValue: purposeRaw) ?? .other
    }
}
