import SwiftUI
import SwiftData

/// Library tab for `InterviewTemplate` records — list/sidebar plus a
/// detail editor in the right pane. Mirrors `RubricListView`'s shape so
/// the two browse experiences feel consistent.
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\InterviewTemplate.lastUsedAt, order: .reverse),
            SortDescriptor(\InterviewTemplate.name)
        ]
    ) private var templates: [InterviewTemplate]

    var body: some View {
        LibrarySidebarScaffold(
            title: "Templates",
            items: templates,
            searchPlaceholder: "Search templates",
            emptyTitle: "No Templates",
            emptySystemImage: "list.bullet.rectangle",
            emptyDescription: "Create reusable interview templates to standardize your loops",
            detailPlaceholderTitle: "No Template Selected",
            detailPlaceholderSystemImage: "list.bullet.rectangle",
            detailPlaceholderDescription: "Select a template to edit",
            isArchived: { $0.isArchived },
            toggleArchive: { $0.isArchived.toggle() },
            duplicate: { duplicateTemplate($0) },
            delete: { modelContext.delete($0) },
            matchesSearch: { template, query in
                let q = query.lowercased()
                return template.name.lowercased().contains(q)
                    || (template.templateDescription?.lowercased().contains(q) ?? false)
            },
            row: { TemplateRowView(template: $0) },
            editor: { TemplateEditorView(template: $0) },
            addSheet: { onCreated in AddTemplateSheet(onCreated: onCreated) }
        )
    }

    /// Deep-clone a template so the user can iterate on a variant without
    /// mutating the original. Phases and role links copy; usage stats
    /// reset.
    private func duplicateTemplate(_ source: InterviewTemplate) {
        let copy = InterviewTemplate(
            name: "\(source.name) (Copy)",
            templateDescription: source.templateDescription,
            iconName: source.iconName,
            appliesToAnyRole: source.appliesToAnyRole
        )
        modelContext.insert(copy)
        clonePhases(from: source, to: copy)
        for link in source.roleLinks {
            let newLink = TemplateRoleLink(
                template: copy,
                role: link.role,
                sortOrder: link.sortOrder
            )
            modelContext.insert(newLink)
            copy.roleLinks.append(newLink)
        }
    }
}

/// Copy every `InterviewTemplatePhase` from `source` to `target`. The
/// only call site for two-step "duplicate template / new from existing"
/// flows — keep the field-by-field copy in one place so adding a new
/// field on `InterviewTemplatePhase` doesn't silently miss one path.
fileprivate func clonePhases(from source: InterviewTemplate, to target: InterviewTemplate) {
    for phase in source.orderedPhases {
        let newPhase = InterviewTemplatePhase(
            title: phase.title,
            kind: phase.kind,
            rubric: phase.rubric,
            sortOrder: phase.sortOrder,
            iconName: phase.iconName,
            targetMinutes: phase.targetMinutes
        )
        newPhase.briefOverride = phase.briefOverride
        newPhase.template = target
        target.phases.append(newPhase)
    }
}

// MARK: - Row

struct TemplateRowView: View {
    let template: InterviewTemplate

    private var scopeText: String {
        if template.appliesToAnyRole { return "Any role" }
        let names = template.roleLinks.compactMap { $0.role?.displayTitle }
        if names.isEmpty { return "Unscoped" }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: template.iconName ?? "list.bullet.rectangle")
                .foregroundStyle(.cyan)
                .frame(width: 22, height: 22)
                .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(scopeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(template.phases.count) phases")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if template.usageCount > 0 {
                        Text("· used \(template.usageCount)x")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Sheet

struct AddTemplateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InterviewTemplate.createdAt, order: .reverse) private var existingTemplates: [InterviewTemplate]
    @State private var name = ""
    @State private var description = ""
    @State private var sourceTemplate: InterviewTemplate?
    var onCreated: (InterviewTemplate) -> Void

    private var activeTemplates: [InterviewTemplate] {
        existingTemplates.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New Template", subtitle: "Reusable interview loop")

            Form {
                TextField("Name", text: $name, prompt: Text("Backend Loop"))
                TextField("Description (optional)", text: $description, prompt: Text("Standard 4-phase loop for backend ICs"), axis: .vertical)
                    .lineLimit(2...4)
                Picker("Copy from (optional)", selection: $sourceTemplate) {
                    Text("Start blank").tag(nil as InterviewTemplate?)
                    ForEach(activeTemplates) { template in
                        Text(template.name).tag(template as InterviewTemplate?)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 220)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    create()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let template = InterviewTemplate(
            name: trimmedName,
            templateDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
            iconName: sourceTemplate?.iconName,
            appliesToAnyRole: sourceTemplate?.appliesToAnyRole ?? true
        )
        modelContext.insert(template)
        if let source = sourceTemplate {
            clonePhases(from: source, to: template)
        } else {
            // Empty template gets the conventional intro/conclusion bookends
            // so the user has something to anchor on.
            let intro = InterviewTemplatePhase(
                title: "Intro",
                kind: .intro,
                sortOrder: 0,
                iconName: "person.wave.2",
                targetMinutes: 5
            )
            intro.template = template
            template.phases.append(intro)
            let conclusion = InterviewTemplatePhase(
                title: "Conclusion",
                kind: .conclusion,
                sortOrder: 1,
                iconName: "questionmark.bubble",
                targetMinutes: 5
            )
            conclusion.template = template
            template.phases.append(conclusion)
        }
        onCreated(template)
    }
}
