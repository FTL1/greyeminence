import Foundation
import SwiftData

@Model
final class Rubric {
    var id: UUID
    var name: String
    var isArchived: Bool
    var createdAt: Date

    var role: InterviewRole?

    @Relationship(deleteRule: .cascade, inverse: \RubricSection.rubric)
    var sections: [RubricSection]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isArchived = false
        self.createdAt = .now
        self.sections = []
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

    func toSnapshot() -> RubricSnapshot {
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
        return RubricSnapshot(name: name, sections: sectionSnapshots)
    }
}
