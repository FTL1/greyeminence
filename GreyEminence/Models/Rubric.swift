import Foundation
import SwiftData

@Model
final class Rubric {
    var id: UUID
    var name: String
    var isArchived: Bool
    var createdAt: Date

    /// Markdown brief that the interviewer hands to the candidate when
    /// this rubric is the active phase — the problem statement /
    /// scenario for the whole phase, not per-section. Surfaced in the
    /// live interview view with Copy + Export-PDF affordances.
    var candidateInstructions: String?

    /// Legacy single-role pointer. Kept for backward compat reads; new
    /// writes go through `roleLinks`. The startup maintenance pass
    /// migrates a non-nil `role` into a single `RoleRubricLink` with
    /// strictness `.standard`.
    var role: InterviewRole?

    /// Many-to-many connection to roles via `RoleRubricLink`. Each link
    /// also carries calibration metadata (strictness) so the same rubric
    /// can apply to multiple roles with different bars.
    @Relationship(deleteRule: .cascade, inverse: \RoleRubricLink.rubric)
    var roleLinks: [RoleRubricLink]

    @Relationship(deleteRule: .cascade, inverse: \RubricSection.rubric)
    var sections: [RubricSection]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isArchived = false
        self.createdAt = .now
        self.sections = []
        self.roleLinks = []
    }

    /// All roles this rubric is linked to (via `roleLinks`), plus the
    /// legacy single `role` if no links exist yet. Convenience for
    /// callers that just want the union — UI surfaces should prefer
    /// `roleLinks` directly so they can also show strictness.
    var linkedRoles: [InterviewRole] {
        let linked = roleLinks.compactMap(\.role)
        if !linked.isEmpty { return linked }
        return role.map { [$0] } ?? []
    }

    /// True when this rubric applies to the given role — checks both the
    /// legacy `role` field and the `roleLinks` join. Used by the phase
    /// planner to filter rubrics for the candidate's role.
    func appliesTo(role queryRole: InterviewRole) -> Bool {
        if role?.id == queryRole.id { return true }
        return roleLinks.contains { $0.role?.id == queryRole.id }
    }

    /// Rescale section weights so they sum to exactly 100. No-op if the
    /// total is already within 0.01 of 100. Pathological all-zero weights
    /// distribute evenly. Called when the rubric editor opens so legacy
    /// rubrics with arbitrary totals (e.g., 50+30+20+25=125) reshape to a
    /// clean 100-total view without a visible jolt mid-edit.
    @MainActor
    func normalizeWeightsToHundred() {
        let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
        guard !sortedSections.isEmpty else { return }
        let total = sortedSections.reduce(0.0) { $0 + max($1.weight, 0) }
        guard total > 0 else {
            let even = 100.0 / Double(sortedSections.count)
            for section in sortedSections { section.weight = even }
            return
        }
        if abs(total - 100) < 0.01 { return }
        let scale = 100.0 / total
        for section in sortedSections {
            section.weight = max(section.weight, 0) * scale
        }
    }

    /// Build a Sendable snapshot for the AI scoring prompt. When `role` is
    /// supplied, the link's per-role strictness is fed through to the
    /// prompt as a calibration directive — same rubric, harder/softer
    /// bar across roles. Falls back to standard (no addendum) when no
    /// role is given or no link matches.
    func toSnapshot(strictnessFor role: InterviewRole? = nil) -> RubricSnapshot {
        let strictness = strictnessFor(role: role)
        let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
        let sectionSnapshots: [RubricSectionSnapshot] = sortedSections.map { section in
            let criterionSnapshots: [CriterionSnapshot] = section.criteria
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { criterion in
                    let llmGuidance = criterion.sortedGuidance(visibleTo: .llm).map(\.text)
                    return CriterionSnapshot(signal: criterion.signal, llmGuidance: llmGuidance)
                }
            let bonusSnapshots: [BonusSignalSnapshot] = section.bonusSignals
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { signal in
                    BonusSignalSnapshot(
                        label: signal.label,
                        expected: signal.expectedAnswer,
                        value: signal.bonusValue
                    )
                }
            return RubricSectionSnapshot(
                id: section.id,
                title: section.title,
                description: section.sectionDescription,
                criteria: criterionSnapshots,
                bonusSignals: bonusSnapshots,
                weight: section.weight
            )
        }
        return RubricSnapshot(
            name: name,
            sections: sectionSnapshots,
            strictnessAddendum: strictness.promptAddendum
        )
    }

    /// Look up the strictness for `role` via this rubric's `roleLinks`.
    /// Defaults to `.standard` when no role is provided or no link matches.
    func strictnessFor(role: InterviewRole?) -> RubricStrictness {
        guard let role else { return .standard }
        return roleLinks.first(where: { $0.role?.id == role.id })?.strictness ?? .standard
    }
}
