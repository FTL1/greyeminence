import Foundation
import SwiftData

/// What kind of phase this is. Codifies what `PlannedPhase.intro/conclusion`
/// has been doing by convention up to now (rubric == nil + a magic title).
enum InterviewTemplatePhaseKind: String, Codable, Sendable {
    /// The unscored opener — candidate intro, recap of resume, expectations.
    case intro
    /// A rubric-evaluated phase (System Design, Coding, etc.).
    case scored
    /// A free-form discussion phase that's not the intro or conclusion —
    /// hallway-track conversations, take-home reviews without a formal
    /// rubric, etc.
    case unscored
    /// The unscored closer — candidate questions, wrap-up, next steps.
    case conclusion
}

/// One phase inside an `InterviewTemplate`. Mirrors the runtime
/// `PlannedPhase` value type but persisted, so the user can save/edit a
/// template independently of any in-flight interview creation.
@Model
final class InterviewTemplatePhase {
    var id: UUID
    var title: String
    var sortOrder: Int
    var iconName: String?
    var kindRawValue: String
    /// Optional minutes the interviewer expects this phase to run. Surfaced
    /// as a soft target during the live interview (no hard cutoff). Nil
    /// when the template doesn't carry timing.
    var targetMinutes: Int?
    /// Optional per-template override of the rubric's `candidateInstructions`.
    /// Schema field is reserved; UI is intentionally not wired to avoid
    /// two-layer brief-override confusion. Field exists now so a future
    /// override UI doesn't need a migration.
    var briefOverride: String?

    var template: InterviewTemplate?
    /// Nil for intro/unscored/conclusion kinds. Required (in spirit) for
    /// `.scored` — the template UI enforces this on save.
    var rubric: Rubric?

    var kind: InterviewTemplatePhaseKind {
        get { InterviewTemplatePhaseKind(rawValue: kindRawValue) ?? .scored }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        title: String,
        kind: InterviewTemplatePhaseKind = .scored,
        rubric: Rubric? = nil,
        sortOrder: Int = 0,
        iconName: String? = nil,
        targetMinutes: Int? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
        self.iconName = iconName
        self.kindRawValue = kind.rawValue
        self.targetMinutes = targetMinutes
        self.briefOverride = nil
        self.rubric = rubric
    }

    /// SF Symbol used in the modal rail / live phase strip when this
    /// template phase is realized as an `InterviewPhase`. Falls back to a
    /// kind-appropriate default.
    var resolvedIconName: String {
        if let iconName, !iconName.isEmpty { return iconName }
        switch kind {
        case .intro: return "person.wave.2"
        case .conclusion: return "questionmark.bubble"
        case .unscored: return "bubble.left.and.bubble.right"
        case .scored: return "list.clipboard"
        }
    }
}
