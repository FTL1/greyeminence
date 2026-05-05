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

    /// Filename of the resume copied into the candidate's directory under
    /// AppSupport. Resolved to a URL via `StorageManager.candidateResumeURL`.
    /// Nil when no resume is attached. We copy the file into our container
    /// at attach time so we don't depend on the original security-scoped
    /// URL surviving across launches.
    var resumeFilename: String?

    /// When the resume was attached (or last replaced). Used in the UI to
    /// give the reader a sense of how stale it might be.
    var resumeAddedAt: Date?

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
