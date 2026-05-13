import Foundation
import SwiftData

@Model
final class InterviewRole {
    var id: UUID
    var customTitle: String?
    var createdAt: Date

    var department: Department?
    var team: Team?
    var level: RoleLevel?

    @Relationship(deleteRule: .cascade, inverse: \Rubric.role)
    var rubrics: [Rubric]

    /// Many-to-many links to rubrics that apply to this role with
    /// per-link strictness metadata. Replaces the legacy
    /// `rubrics` one-to-many for new code.
    @Relationship(deleteRule: .cascade, inverse: \RoleRubricLink.role)
    var roleRubricLinks: [RoleRubricLink]

    /// Many-to-many links to interview templates that apply to this role.
    /// Mirrors `roleRubricLinks` (and `TemplateRoleLink` mirrors
    /// `RoleRubricLink`'s shape).
    @Relationship(deleteRule: .cascade, inverse: \TemplateRoleLink.role)
    var templateRoleLinks: [TemplateRoleLink]

    init(level: RoleLevel? = nil, department: Department? = nil, team: Team? = nil, customTitle: String? = nil) {
        self.id = UUID()
        self.level = level
        self.department = department
        self.team = team
        self.customTitle = customTitle
        self.createdAt = .now
        self.rubrics = []
        self.roleRubricLinks = []
        self.templateRoleLinks = []
    }

    var displayTitle: String {
        if let title = customTitle { return title }
        if let lvl = level, !lvl.isDeleted { return lvl.name }
        return "Unknown"
    }

    var fullDescription: String {
        var parts: [String] = []
        if let dept = department, !dept.isDeleted { parts.append(dept.name) }
        if let t = team, !t.isDeleted { parts.append(t.name) }
        parts.append(displayTitle)
        return parts.joined(separator: " — ")
    }
}
