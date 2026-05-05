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
