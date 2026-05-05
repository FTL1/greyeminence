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

    var interview: Interview?
    var rubric: Rubric?

    @Relationship(deleteRule: .cascade, inverse: \InterviewSectionScore.phase)
    var sectionScores: [InterviewSectionScore]

    var status: InterviewPhaseStatus {
        get { InterviewPhaseStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        title: String,
        rubric: Rubric? = nil,
        plannedOrder: Int = 0,
        status: InterviewPhaseStatus = .planned
    ) {
        self.id = UUID()
        self.title = title
        self.rubric = rubric
        self.plannedOrder = plannedOrder
        self.statusRawValue = status.rawValue
        self.createdAt = .now
        self.sectionScores = []
    }

    /// True when this phase has a rubric and is therefore eligible for AI
    /// scoring. Intro/conclusion phases (no rubric) are skipped by the
    /// analysis loop.
    var isScored: Bool { rubric != nil }
}
