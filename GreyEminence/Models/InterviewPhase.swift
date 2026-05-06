import Foundation
import SwiftData

/// Status of an `InterviewPhase`. Phases progress from `.planned` (created at
/// pre-call setup but not yet active) → `.active` (currently being recorded
/// and scored) → `.completed` (finished, scores frozen). `.skipped` records
/// that the interviewer chose not to run a planned phase.
enum InterviewPhaseStatus: String, Codable, Sendable {
    case planned
    case active
    case completed
    case skipped
}

/// One phase of a multi-rubric interview. An interview composes a sequence of
/// phases (e.g., System Design → Coding → Code Review), each with its own
/// rubric and its own scoring window. Phases are the unit of AI scoring:
/// only one phase is active at a time, and AI analysis is bounded to
/// segments captured between `startedAt` and `endedAt` against the phase's
/// `rubric`.
///
/// Rationale: this replaces the old "single rubric per interview" assumption.
/// It also subsumes the special-cased intro/conclusion sections — those are
/// now phases with `rubric == nil` (no scoring, just transcript anchoring).
@Model
final class InterviewPhase {
    var id: UUID
    var title: String
    var statusRawValue: String
    var plannedOrder: Int
    var startedAt: Date?
    var endedAt: Date?
    var createdAt: Date
    /// SF Symbol name for the phase chip / icon strip. Nil falls back to a
    /// computed default (`person.wave.2` for intro, `questionmark.bubble`
    /// for conclusion, `list.clipboard` for any scored phase). Letting
    /// the user pick gives system-design vs coding vs take-home a
    /// distinguishable glance.
    var iconName: String?
    /// Soft-target duration in minutes carried over from the template
    /// phase. The live UI shows this as a pill ("45 min") and warns when
    /// elapsed time exceeds the target by ~25%. Nil = no target.
    var targetMinutes: Int?

    var interview: Interview?
    var rubric: Rubric?

    @Relationship(deleteRule: .cascade, inverse: \InterviewSectionScore.phase)
    var sectionScores: [InterviewSectionScore]

    /// Notes captured while this phase was active. Phase deletion nullifies
    /// the back-reference rather than cascading — notes live independently
    /// on the interview and outlive the phase.
    @Relationship(deleteRule: .nullify, inverse: \InterviewNote.phase)
    var notes: [InterviewNote]

    var status: InterviewPhaseStatus {
        get { InterviewPhaseStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        title: String,
        rubric: Rubric? = nil,
        plannedOrder: Int = 0,
        status: InterviewPhaseStatus = .planned,
        iconName: String? = nil,
        targetMinutes: Int? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.rubric = rubric
        self.plannedOrder = plannedOrder
        self.statusRawValue = status.rawValue
        self.iconName = iconName
        self.targetMinutes = targetMinutes
        self.createdAt = .now
        self.sectionScores = []
        self.notes = []
    }

    /// True when this phase has a rubric and is therefore eligible for AI
    /// scoring. Intro/conclusion phases (no rubric) are skipped by the
    /// analysis loop.
    var isScored: Bool { rubric != nil }

    /// Resolved SF Symbol — explicit `iconName` if set, else a default
    /// based on whether the phase is an intro/conclusion (unscored)
    /// or a scored rubric phase. The intro/conclusion fallbacks are
    /// keyed on title rather than position so renamed phases still
    /// pick a sensible icon.
    var resolvedIconName: String {
        if let iconName, !iconName.isEmpty { return iconName }
        let lower = title.lowercased()
        if lower.contains("intro") { return "person.wave.2" }
        if lower.contains("conclusion") || lower.contains("wrap") || lower.contains("q&a") {
            return "questionmark.bubble"
        }
        return rubric != nil ? "list.clipboard" : "bubble.left.and.bubble.right"
    }
}

/// Curated SF Symbols a user can pick from for a phase. Kept short so
/// the menu stays scannable. Add to taste — anything in SF Symbols
/// works at runtime, this is just the picker affordance.
enum PhaseIconCatalog {
    static let symbols: [String] = [
        "person.wave.2",
        "list.clipboard",
        "questionmark.bubble",
        "bubble.left.and.bubble.right",
        "chevron.left.slash.chevron.right",
        "rectangle.connected.to.line.below",
        "ruler",
        "wand.and.stars",
        "brain.head.profile",
        "hammer",
        "graduationcap",
        "chart.bar.doc.horizontal",
        "doc.text.magnifyingglass",
        "person.2.wave.2",
        "lightbulb",
        "puzzlepiece.extension",
        "terminal",
        "sparkles"
    ]
}
