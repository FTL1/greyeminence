import SwiftUI
import SwiftData

/// Library tab for `InterviewTemplate` records — list/sidebar plus a
/// detail editor in the right pane. Mirrors `RubricListView`'s shape so
/// the two browse experiences feel consistent.
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewTemplate.lastUsedAt, order: .reverse) private var templates: [InterviewTemplate]
    @State private var selectedTemplate: InterviewTemplate?
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var showArchived = false

    private var filteredTemplates: [InterviewTemplate] {
        let visible = templates.filter { showArchived || !$0.isArchived }
        if searchText.isEmpty { return visible }
        let query = searchText.lowercased()
        return visible.filter {
            $0.name.lowercased().contains(query) ||
            ($0.templateDescription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTemplates, selection: $selectedTemplate) { template in
                TemplateRowView(template: template)
                    .tag(template)
                    .opacity(template.isArchived ? 0.5 : 1)
                    .contextMenu {
                        Button(template.isArchived ? "Unarchive" : "Archive") {
                            template.isArchived.toggle()
                        }
                        Button("Duplicate") {
                            duplicateTemplate(template)
                        }
                        Button("Delete", role: .destructive) {
                            if selectedTemplate == template { selectedTemplate = nil }
                            modelContext.delete(template)
                        }
                    }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search templates")
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Label("Add Template", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    .help(showArchived ? "Hide archived" : "Show archived")
                }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create reusable interview templates to standardize your loops")
                    )
                } else if filteredTemplates.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddTemplateSheet { template in
                    selectedTemplate = template
                }
            }
        } detail: {
            if let template = selectedTemplate {
                TemplateEditorView(template: template)
            } else {
                ContentUnavailableView(
                    "No Template Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Select a template to edit")
                )
            }
        }
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
            newPhase.template = copy
            copy.phases.append(newPhase)
        }
        for link in source.roleLinks {
            let newLink = TemplateRoleLink(
                template: copy,
                role: link.role,
                sortOrder: link.sortOrder
            )
            modelContext.insert(newLink)
            copy.roleLinks.append(newLink)
        }
        selectedTemplate = copy
    }
}

// MARK: - Row

private struct TemplateRowView: View {
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

private struct AddTemplateSheet: View {
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
            Text("New Template")
                .font(.headline)
                .padding()

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
                newPhase.template = template
                template.phases.append(newPhase)
            }
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
