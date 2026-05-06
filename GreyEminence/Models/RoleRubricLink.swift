import Foundation
import SwiftData
import SwiftUI

/// How strictly the AI should grade against the rubric for a given role.
/// Doesn't gate which rubric is *available* — just shifts the calibration
/// in the AI scoring prompt. Standard is the default; lenient/strict are
/// optional knobs the interviewer can dial up or down.
enum RubricStrictness: String, Codable, CaseIterable, Sendable {
    case lenient
    case standard
    case strict

    var label: String {
        switch self {
        case .lenient: "Lenient"
        case .standard: "Standard"
        case .strict: "Strict"
        }
    }

    var symbolName: String {
        switch self {
        case .lenient: "tortoise"
        case .standard: "scalemass"
        case .strict: "flame"
        }
    }

    var color: Color {
        switch self {
        case .lenient: .blue
        case .standard: .secondary
        case .strict: .orange
        }
    }

    /// AI-prompt addendum describing this calibration. Used by #16 (feed
    /// strictness into AI scoring prompt). Empty string for `.standard`
    /// since that's the default and doesn't need extra prompting.
    var promptAddendum: String {
        switch self {
        case .lenient:
            "Grade leniently for this role — the candidate is at an earlier career stage. A B+ requires solid competence, not exceptional performance."
        case .standard:
            ""
        case .strict:
            "Grade strictly for this role — the bar is high. A B+ requires demonstrating evidence beyond competence; A grades require exceptional performance."
        }
    }
}

/// Join model linking one `Rubric` to one `InterviewRole`, with extra
/// metadata about how the rubric should be applied for that role.
/// Replaces the prior 1-to-1 `Rubric.role` relationship — the same
/// rubric (e.g., "System Design") can now apply to many senior roles
/// without duplicating the rubric content.
@Model
final class RoleRubricLink {
    var id: UUID
    var strictnessRawValue: String
    var sortOrder: Int
    var createdAt: Date

    var rubric: Rubric?
    var role: InterviewRole?

    var strictness: RubricStrictness {
        get { RubricStrictness(rawValue: strictnessRawValue) ?? .standard }
        set { strictnessRawValue = newValue.rawValue }
    }

    init(
        rubric: Rubric? = nil,
        role: InterviewRole? = nil,
        strictness: RubricStrictness = .standard,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.rubric = rubric
        self.role = role
        self.strictnessRawValue = strictness.rawValue
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}
