import Foundation
import SwiftData
import SwiftUI

enum InterviewStatus: String, Codable, Sendable {
    case scheduled
    case recording
    case completed
    case archived
}

enum OverallRecommendation: Int, Codable, CaseIterable, Sendable {
    case strongNoHire = 1
    case noHire = 2
    case leanNoHire = 3
    case neutral = 4
    case leanHire = 5
    case hire = 6
    case strongHire = 7

    var label: String {
        switch self {
        case .strongNoHire: "Strong No Hire"
        case .noHire: "No Hire"
        case .leanNoHire: "Lean No Hire"
        case .neutral: "Neutral"
        case .leanHire: "Lean Hire"
        case .hire: "Hire"
        case .strongHire: "Strong Hire"
        }
    }

    var color: Color {
        switch self {
        case .strongNoHire: .red
        case .noHire: .red.opacity(0.7)
        case .leanNoHire: .orange
        case .neutral: .gray
        case .leanHire: .yellow
        case .hire: .green.opacity(0.8)
        case .strongHire: .green
        }
    }

    var shortLabel: String {
        switch self {
        case .strongNoHire: "SN"
        case .noHire: "N"
        case .leanNoHire: "LN"
        case .neutral: "—"
        case .leanHire: "LH"
        case .hire: "H"
        case .strongHire: "SH"
        }
    }
}

@Model
final class Interview {
    var id: UUID
    var statusRawValue: String
    var interviewerNotes: String?
    var recommendationRawValue: Int?
    var strengths: [String] = []
    var weaknesses: [String] = []
    var redFlags: [String] = []
    var overallAssessment: String?
    var createdAt: Date

    /// When the AI last scored this interview — set by the end-of-interview
    /// final analysis and by a manual "Score All Sections" run. Nil until
    /// the first scoring pass. Surfaced in the scorecard header.
    var lastScoredAt: Date?

    /// When the interview is planned to happen — chosen at scheduling time.
    /// Optional so historical interviews (created before this field
    /// existed) and ad-hoc "start now" sessions don't need a value. Falls
    /// back to `createdAt` in the list display.
    var scheduledAt: Date?

    /// Set by app-launch orphan recovery when a `.recording` row had to be
    /// reverted to `.scheduled` because the audio engine wasn't actually
    /// running (crash / app restart mid-interview). Surfaces a badge on
    /// the list so the user can spot interrupted sessions amongst the
    /// regular scheduled ones. Cleared when the interview is started or
    /// completed cleanly.
    var interruptedAt: Date?

    var candidate: Candidate?
    var rubric: Rubric?

    /// Template this interview was scheduled from. Optional — interviews
    /// scheduled from a blank plan have no template. The relation is
    /// nullable so deleting a template doesn't cascade-destroy historical
    /// interviews; the denormalized `templateNameAtSchedule` snapshot
    /// below is the analytical fallback for that case.
    var template: InterviewTemplate?
    /// Snapshot of the template's name at the moment of scheduling.
    /// Survives template renames and deletes — the scorecard renders this
    /// directly so historical interviews always show the loop they were
    /// run under, even if the template has since been edited.
    var templateNameAtSchedule: String?

    @Relationship(deleteRule: .cascade)
    var meeting: Meeting?

    @Relationship(deleteRule: .cascade, inverse: \InterviewSectionScore.interview)
    var sectionScores: [InterviewSectionScore]

    /// Ordered phases that compose this interview. Each phase has its own
    /// rubric (or none, for intro/conclusion) and scoring window. No
    /// `= []` default — SwiftData migration on macOS 26 chokes on
    /// default literals for new relationships.
    @Relationship(deleteRule: .cascade, inverse: \InterviewPhase.interview)
    var phases: [InterviewPhase]

    @Relationship(deleteRule: .cascade, inverse: \InterviewImpression.interview)
    var impressions: [InterviewImpression]

    @Relationship(deleteRule: .cascade, inverse: \InterviewBookmark.interview)
    var bookmarks: [InterviewBookmark]

    @Relationship(deleteRule: .cascade, inverse: \InterviewNote.interview)
    var notes: [InterviewNote]

    @Relationship(deleteRule: .nullify)
    var interviewers: [Contact]

    var status: InterviewStatus {
        get { InterviewStatus(rawValue: statusRawValue) ?? .scheduled }
        set { statusRawValue = newValue.rawValue }
    }

    var overallRecommendation: OverallRecommendation? {
        get { recommendationRawValue.flatMap { OverallRecommendation(rawValue: $0) } }
        set { recommendationRawValue = newValue?.rawValue }
    }

    init(candidate: Candidate? = nil, rubric: Rubric? = nil) {
        self.id = UUID()
        self.statusRawValue = InterviewStatus.scheduled.rawValue
        self.candidate = candidate
        self.rubric = rubric
        self.createdAt = .now
        self.sectionScores = []
        self.phases = []
        self.impressions = []
        self.bookmarks = []
        self.notes = []
        self.interviewers = []
    }

    /// Phases ordered by their planned position. Use this for display and
    /// transition navigation rather than relying on `phases` insertion order.
    var orderedPhases: [InterviewPhase] {
        phases.sorted { $0.plannedOrder < $1.plannedOrder }
    }

    /// The phase currently `.active`, if any. There should be at most one.
    var activePhase: InterviewPhase? {
        phases.first(where: { $0.status == .active })
    }

    var compositeGradePoints: Double? {
        let scored = sectionScores.compactMap { score -> (Double, Double)? in
            guard let gp = score.effectiveGradePoints else { return nil }
            return (gp, score.weight)
        }
        guard !scored.isEmpty else { return nil }
        let totalWeight = scored.reduce(0.0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        return scored.reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    /// After a scoring pass, any section with no grade at all (AI couldn't
    /// grade it, interviewer didn't either) counts as a failure — an
    /// undiscussed rubric area is a missed signal, not a neutral blank.
    /// Phases that were planned but never run land here wholesale. An
    /// interviewer grade always wins; an existing AI grade is left alone.
    func markUncoveredSectionsAsFailing() {
        for score in sectionScores where !score.isDeleted && score.effectiveGrade == nil {
            let phaseNeverRan = score.phase.map { $0.startedAt == nil } ?? false
            score.aiGrade = .f
            score.aiConfidence = nil
            score.aiRationale = phaseNeverRan
                ? "This phase was not conducted during the interview."
                : "Not discussed during the interview — no evidence to evaluate."
        }
    }
}
