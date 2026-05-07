import SwiftUI
import SwiftData

struct RubricListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rubric.createdAt, order: .reverse) private var rubrics: [Rubric]

    var body: some View {
        LibrarySidebarScaffold(
            title: "Rubrics",
            items: rubrics,
            searchPlaceholder: "Search rubrics",
            emptyTitle: "No Rubrics",
            emptySystemImage: "list.clipboard",
            emptyDescription: "Create rubrics to evaluate interview candidates",
            detailPlaceholderTitle: "No Rubric Selected",
            detailPlaceholderSystemImage: "list.clipboard",
            detailPlaceholderDescription: "Select a rubric to edit",
            isArchived: { $0.isArchived },
            toggleArchive: { $0.isArchived.toggle() },
            duplicate: { duplicateRubric($0) },
            delete: { modelContext.delete($0) },
            matchesSearch: { rubric, query in
                let q = query.lowercased()
                return rubric.name.lowercased().contains(q)
                    || (rubric.role?.displayTitle.lowercased().contains(q) ?? false)
            },
            row: { RubricRowView(rubric: $0) },
            editor: { RubricEditorView(rubric: $0) },
            addSheet: { onCreated in AddRubricSheet(onCreated: onCreated) }
        )
    }

    private func duplicateRubric(_ source: Rubric) {
        let copy = Rubric(name: "\(source.name) (Copy)")
        copy.role = source.role
        modelContext.insert(copy)
        deepCopyRubricContents(from: source, to: copy)
    }
}

// MARK: - Row View

struct RubricRowView: View {
    let rubric: Rubric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rubric.name)
                .font(.body)
            HStack(spacing: 6) {
                if let role = rubric.role {
                    Text(role.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(rubric.sections.count) sections")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Sheet

struct AddRubricSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]
    @Query(sort: \Rubric.createdAt, order: .reverse) private var existingRubrics: [Rubric]
    @State private var name = ""
    @State private var selectedRole: InterviewRole?
    @State private var sourceRubric: Rubric?
    var onCreated: (Rubric) -> Void

    private var defaultName: String {
        guard let role = selectedRole else { return "Interview Rubric" }
        return "\(role.displayTitle) Interview"
    }

    private var activeRubrics: [Rubric] {
        existingRubrics.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New Rubric", subtitle: "Scoring template for one phase")

            Form {
                Picker("Role", selection: $selectedRole) {
                    Text("Select a role...").tag(nil as InterviewRole?)
                    ForEach(roles) { role in
                        Text(role.fullDescription).tag(role as InterviewRole?)
                    }
                }
                TextField("Name (optional)", text: $name, prompt: Text(defaultName))
                Picker("Copy from (optional)", selection: $sourceRubric) {
                    Text("Start blank").tag(nil as Rubric?)
                    ForEach(activeRubrics) { rubric in
                        Text(rubric.name).tag(rubric as Rubric?)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 180)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let rubric = Rubric(name: trimmed.isEmpty ? defaultName : trimmed)
                    rubric.role = selectedRole
                    modelContext.insert(rubric)
                    if let source = sourceRubric {
                        deepCopyRubricContents(from: source, to: rubric)
                    }
                    onCreated(rubric)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedRole == nil)
            }
            .padding()
        }
        .frame(width: 400)
    }

}

// MARK: - Shared Deep Copy

private func deepCopyRubricContents(from source: Rubric, to target: Rubric) {
    for section in source.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
        let newSection = RubricSection(
            title: section.title,
            description: section.sectionDescription,
            sortOrder: section.sortOrder,
            weight: section.weight
        )
        newSection.rubric = target
        for criterion in section.criteria.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let newCriterion = RubricCriterion(
                signal: criterion.signal,
                sortOrder: criterion.sortOrder,
                evaluationNotes: criterion.evaluationNotes
            )
            newCriterion.section = newSection
            // Carry over guidance bullets so the duplicated rubric is a
            // true clone, not a stripped-down copy.
            for guidance in criterion.guidance.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let copy = CriterionGuidance(
                    text: guidance.text,
                    audience: guidance.audience,
                    sortOrder: guidance.sortOrder
                )
                copy.criterion = newCriterion
            }
        }
        for signal in section.bonusSignals.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let newSignal = RubricBonusSignal(
                label: signal.label,
                expectedAnswer: signal.expectedAnswer,
                bonusValue: signal.bonusValue,
                sortOrder: signal.sortOrder
            )
            newSignal.section = newSection
        }
    }
}
