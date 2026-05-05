import Foundation
import SwiftData

@Model
final class RubricCriterion {
    var id: UUID
    var signal: String
    /// Legacy free-text evaluation note. Kept for backward compat; new UI
    /// reads/writes via `guidance` bullets. The startup maintenance pass
    /// migrates non-empty values into a single guidance bullet
    /// (audience: interviewer).
    var evaluationNotes: String?
    var sortOrder: Int

    var section: RubricSection?

    /// Audience-tagged guidance bullets attached to this criterion. Some
    /// bullets are for the interviewer's own reference; others are
    /// appended to the rubric snapshot fed to the AI scoring prompt so
    /// the model scores against the same interpretation.
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
