import Foundation
import SwiftData

/// A reusable, named interview plan: an ordered sequence of phases (each
/// optionally tied to a rubric) plus role-scope metadata. Templates are
/// the "loops you run" — composed of rubrics (which define *what* to
/// evaluate) but distinct from them: a template carries the running order,
/// the unscored intro/conclusion bookends, and per-phase timing.
///
/// Relationship to existing models:
/// - `Rubric` defines criteria — unchanged, reused across templates.
/// - `RoleRubricLink` says "this rubric is relevant to this role" — that's
///   the *discovery* layer the modal's palette pulls from.
/// - `InterviewTemplate` is the *curation* layer: a named subset of those
///   rubrics in a chosen order, ready to schedule.
/// - `Interview.phases` are *snapshots* of the template at scheduling
///   time — editing a template later does not rewrite scheduled interviews.
@Model
final class InterviewTemplate {
    var id: UUID
    var name: String
    /// Free-form description shown in the library. Avoid the property name
    /// `description` — it shadows `CustomStringConvertible`.
    var templateDescription: String?
    /// SF Symbol shown in the library row + creation modal rail. Falls
    /// back to "list.bullet.rectangle" when nil.
    var iconName: String?
    /// Archived templates stay in the store for reference but are hidden
    /// from the creation modal and library by default.
    var isArchived: Bool
    /// When true, the template is offered for any candidate role and the
    /// `roleLinks` join is ignored for filtering. Pragmatic shortcut so
    /// universal templates ("Bar Raiser") don't need 30 link rows.
    var appliesToAnyRole: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Last time the template was used to schedule an interview. Drives
    /// the "Recently used" section of the modal rail.
    var lastUsedAt: Date?
    /// Bumped on each schedule. Used for sorting and as a "popularity"
    /// signal in the library.
    var usageCount: Int

    @Relationship(deleteRule: .cascade, inverse: \InterviewTemplatePhase.template)
    var phases: [InterviewTemplatePhase]

    @Relationship(deleteRule: .cascade, inverse: \TemplateRoleLink.template)
    var roleLinks: [TemplateRoleLink]

    init(
        name: String,
        templateDescription: String? = nil,
        iconName: String? = nil,
        appliesToAnyRole: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.templateDescription = templateDescription
        self.iconName = iconName
        self.isArchived = false
        self.appliesToAnyRole = appliesToAnyRole
        self.createdAt = .now
        self.updatedAt = .now
        self.lastUsedAt = nil
        self.usageCount = 0
        self.phases = []
        self.roleLinks = []
    }

    var orderedPhases: [InterviewTemplatePhase] {
        phases.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// True when this template should appear as a default suggestion for
    /// the given role: either the universal flag is set, or there's an
    /// explicit link.
    func appliesTo(role: InterviewRole) -> Bool {
        if appliesToAnyRole { return true }
        return roleLinks.contains { $0.role?.id == role.id }
    }
}
