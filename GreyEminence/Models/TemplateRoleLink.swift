import Foundation
import SwiftData

/// Many-to-many join between `InterviewTemplate` and `InterviewRole`.
/// Mirrors `RoleRubricLink`'s shape so the mental model stays consistent:
/// templates apply to one or more roles, and the creation modal's
/// "Recommended templates" rail filters via these links (plus the
/// `appliesToAnyRole` escape hatch on the template).
@Model
final class TemplateRoleLink {
    var id: UUID
    var sortOrder: Int
    var createdAt: Date

    var template: InterviewTemplate?
    var role: InterviewRole?

    init(
        template: InterviewTemplate? = nil,
        role: InterviewRole? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.template = template
        self.role = role
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}
