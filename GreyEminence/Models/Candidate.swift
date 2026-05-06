import Foundation
import SwiftData
import SwiftUI

@Model
final class Candidate {
    var id: UUID
    var name: String
    var email: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: Date

    /// Filename of the resume copied into the candidate's directory.
    /// Resolved via `StorageManager.candidateResumeURL`.
    var resumeFilename: String?
    var resumeAddedAt: Date?

    /// AI-generated summary of the resume, used as the candidate-context
    /// prelude in the live interview AI prompt instead of the raw 8K-char
    /// dump. Generated once at attach time; nil while the analysis hasn't
    /// completed (or failed). Caller falls back to truncated raw text.
    var resumeSummary: String?

    /// JSON-encoded `CharacterSheet` generated alongside the summary.
    /// Decoded via `CharacterSheet.fromJSON`. Stored as JSON because the
    /// shape evolves with prompt iteration; we don't want to migrate the
    /// schema every time a field changes.
    var characterSheetJSON: String?

    /// Timestamp of the most recent successful resume analysis. Used in
    /// the UI to show staleness, and to decide whether re-attaching a
    /// resume should re-trigger analysis.
    var resumeAnalyzedAt: Date?

    var role: InterviewRole?

    @Relationship(deleteRule: .nullify, inverse: \Interview.candidate)
    var interviews: [Interview]

    init(name: String, email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.isArchived = false
        self.createdAt = .now
        self.interviews = []
    }

    /// Resolved on-disk URL for the attached resume, or nil if none.
    var resumeURL: URL? {
        resumeFilename.map { StorageManager.shared.candidateResumeURL(for: id, filename: $0) }
    }

    /// Decoded character sheet, if one's been generated.
    var characterSheet: CharacterSheet? {
        CharacterSheet.fromJSON(characterSheetJSON)
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var avatarColor: Color {
        Self.candidateColors[Self.colorIndex(for: name)]
    }

    private static let candidateColors: [Color] = [
        .cyan, .teal, .mint, .green,
        .blue, .indigo, .purple, .pink,
    ]

    private static func colorIndex(for name: String) -> Int {
        var hasher = Hasher()
        hasher.combine(name)
        return abs(hasher.finalize()) % candidateColors.count
    }
}
