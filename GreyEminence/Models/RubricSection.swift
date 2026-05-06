import Foundation
import SwiftData

@Model
final class RubricSection {
    var id: UUID
    var title: String
    var sectionDescription: String
    var sortOrder: Int
    var weight: Double
    var createdAt: Date

    /// Markdown instructions the interviewer hands to the candidate for
    /// this section — typically a problem statement or scenario brief.
    /// Surfaced in the live interview view with Copy + Export-PDF
    /// affordances so the interviewer can paste it into chat or share
    /// it as a file. Optional; sections without instructions just hide
    /// the panel.
    var candidateInstructions: String?

    var rubric: Rubric?

    @Relationship(deleteRule: .cascade, inverse: \RubricCriterion.section)
    var criteria: [RubricCriterion]

    @Relationship(deleteRule: .cascade, inverse: \RubricBonusSignal.section)
    var bonusSignals: [RubricBonusSignal]

    init(title: String, description: String, sortOrder: Int = 0, weight: Double = 1.0) {
        self.id = UUID()
        self.title = title
        self.sectionDescription = description
        self.sortOrder = sortOrder
        self.weight = weight
        self.createdAt = .now
        self.criteria = []
        self.bonusSignals = []
    }
}
