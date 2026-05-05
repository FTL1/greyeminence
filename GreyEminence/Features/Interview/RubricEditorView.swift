import SwiftUI
import SwiftData

struct RubricEditorView: View {
    @Bindable var rubric: Rubric
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]

    private var sortedSections: [RubricSection] {
        rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            // Header
            Section("Rubric Details") {
                TextField("Name", text: $rubric.name)
                Picker("Role", selection: Binding(
                    get: { rubric.role },
                    set: { rubric.role = $0 }
                )) {
                    Text("None").tag(nil as InterviewRole?)
                    ForEach(roles) { role in
                        Text(role.fullDescription).tag(role as InterviewRole?)
                    }
                }
            }

            if !rubric.sections.isEmpty {
                Section {
                    RubricWeightBar(rubric: rubric)
                        .padding(.vertical, 4)
                } header: {
                    Text("Section Weights")
                } footer: {
                    Text("Drag the dividers to redistribute weight. The total always sums to 100%.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Sections
            ForEach(sortedSections) { section in
                RubricSectionEditorView(section: section, onDelete: {
                    let removedWeight = section.weight
                    rubric.sections.removeAll { $0.id == section.id }
                    modelContext.delete(section)
                    // Redistribute the deleted section's weight evenly
                    // across the survivors so the bar stays at 100%.
                    let survivors = rubric.sections
                    if !survivors.isEmpty && removedWeight > 0 {
                        let bonus = removedWeight / Double(survivors.count)
                        for s in survivors { s.weight += bonus }
                    }
                })
            }

            // Add section button
            Section {
                Button {
                    addSection()
                } label: {
                    Label("Add Section", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(rubric.name)
        .onAppear {
            RubricWeightBar.normalizeToHundred(rubric)
        }
    }

    private func addSection() {
        // New section claims a fair share of the existing total. Pull a
        // proportional slice off each existing section so the bar stays
        // at 100% and the new section appears with a meaningful weight.
        let existing = rubric.sections
        let newCount = existing.count + 1
        let newShare = 100.0 / Double(newCount)
        // Shrink existing sections proportionally to their current
        // weights — keeps relative ordering of weights stable.
        let remainingTotal = 100.0 - newShare
        let currentTotal = existing.reduce(0.0) { $0 + max($1.weight, 0) }
        if currentTotal > 0 {
            let scale = remainingTotal / currentTotal
            for s in existing { s.weight = max(s.weight, 0) * scale }
        }
        let section = RubricSection(
            title: "New Section",
            description: "",
            sortOrder: existing.count,
            weight: newShare
        )
        section.rubric = rubric
        rubric.sections.append(section)
    }
}
