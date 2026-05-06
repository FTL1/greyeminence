import Foundation
import SwiftData

@Model
final class RubricCriterion {
    var id: UUID
    var signal: String
    /// Legacy free-text note; migrated to a guidance bullet by
    /// `MaintenanceService.backfillCriterionGuidance`.
    var evaluationNotes: String?
    var sortOrder: Int

    var section: RubricSection?

    @Relationship(deleteRule: .cascade, inverse: \CriterionGuidance.criterion)
    var guidance: [CriterionGuidance]

    init(signal: String, sortOrder: Int = 0, evaluationNotes: String? = nil) {
        self.id = UUID()
        self.signal = signal
        self.sortOrder = sortOrder
        self.evaluationNotes = evaluationNotes
        self.guidance = []
    }

    /// Bullets sorted for display, optionally filtered by audience.
    func sortedGuidance(visibleTo audience: GuidanceAudience? = nil) -> [CriterionGuidance] {
        let sorted = guidance.sorted { $0.sortOrder < $1.sortOrder }
        guard let audience else { return sorted }
        return sorted.filter { item in
            switch audience {
            case .interviewer: return item.audience.visibleToInterviewer
            case .llm: return item.audience.visibleToLLM
            case .both: return true
            }
        }
    }
}
