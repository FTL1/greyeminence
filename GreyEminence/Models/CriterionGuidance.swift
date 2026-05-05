import Foundation
import SwiftData

/// Who a piece of guidance on a `RubricCriterion` is intended for. Bullets
/// directed at the *interviewer* are display-only — they live in the
/// rubric editor as a reminder of what to listen for. Bullets directed
/// at the *llm* are appended to the criterion in the rubric snapshot
/// fed into the AI scoring prompt, so the model uses the same
/// interpretation the interviewer has in mind. `both` shows up in both
/// places.
enum GuidanceAudience: String, Codable, CaseIterable, Sendable {
    case interviewer
    case llm
    case both

    var label: String {
        switch self {
        case .interviewer: "Interviewer"
        case .llm: "AI"
        case .both: "Both"
        }
    }

    var symbolName: String {
        switch self {
        case .interviewer: "person"
        case .llm: "brain"
        case .both: "person.and.background.dotted"
        }
    }

    /// True when a bullet for this audience should be included in the
    /// rubric snapshot sent to the AI.
    var visibleToLLM: Bool {
        self == .llm || self == .both
    }

    /// True when a bullet for this audience should be displayed to the
    /// human interviewer in the rubric editor.
    var visibleToInterviewer: Bool {
        self == .interviewer || self == .both
    }
}

/// One piece of structured guidance attached to a `RubricCriterion`.
/// Replaces the prior single `evaluationNotes` string with a list of
/// audience-tagged bullets. Existing `evaluationNotes` values are
/// migrated to a single guidance bullet (audience: interviewer) by the
/// startup maintenance pass.
@Model
final class CriterionGuidance {
    var id: UUID
    var text: String
    var audienceRawValue: String
    var sortOrder: Int
    var createdAt: Date

    var criterion: RubricCriterion?

    var audience: GuidanceAudience {
        get { GuidanceAudience(rawValue: audienceRawValue) ?? .interviewer }
        set { audienceRawValue = newValue.rawValue }
    }

    init(text: String, audience: GuidanceAudience = .interviewer, sortOrder: Int = 0) {
        self.id = UUID()
        self.text = text
        self.audienceRawValue = audience.rawValue
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}
