import Foundation
import SwiftData

@Model
final class InterviewImpression {
    var id: UUID
    var traitName: String
    /// Interviewer's read on this trait (1–5). Always set; defaults to 3.
    var value: Int
    /// AI's independent read on this trait (1–5), nil until the rubric
    /// analysis loop has produced one. Held separately from `value` so
    /// the AI never clobbers the interviewer's manual rating.
    var aiValue: Int?
    var createdAt: Date

    var interview: Interview?

    init(traitName: String, value: Int = 3) {
        self.id = UUID()
        self.traitName = traitName
        self.value = min(max(value, 1), 5)
        self.aiValue = nil
        self.createdAt = .now
    }
}
