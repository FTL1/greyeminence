import SwiftUI
import SwiftData

struct RubricEditorView: View {
    @Bindable var rubric: Rubric
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]

    private var sortedSections: [RubricSection] {
        rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedLinks: [RoleRubricLink] {
        rubric.roleLinks.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var unlinkedRoles: [InterviewRole] {
        let linkedIDs = Set(rubric.roleLinks.compactMap(\.role?.id))
        return roles.filter { !linkedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            // Header
            Section("Rubric Details") {
                TextField("Name", text: $rubric.name)
            }

            Section {
                if sortedLinks.isEmpty {
                    Text("Not linked to any role yet — this rubric is available everywhere via the phase planner's full list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedLinks) { link in
                    roleLinkRow(link)
                }
                if !unlinkedRoles.isEmpty {
                    Menu {
                        ForEach(unlinkedRoles) { role in
                            Button(role.fullDescription) {
                                addRoleLink(role: role)
                            }
                        }
                    } label: {
                        Label("Add Role", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Applies To")
            } footer: {
                Text("Linking a rubric to a role makes it the default suggestion in the phase planner for candidates in that role. Strictness shifts how harshly the AI grades — \"Standard\" is the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            rubric.normalizeWeightsToHundred()
        }
    }

    // MARK: - Role Link UI

    @ViewBuilder
    private func roleLinkRow(_ link: RoleRubricLink) -> some View {
        HStack(spacing: 8) {
            Image(systemName: link.strictness.symbolName)
                .foregroundStyle(link.strictness.color)
                .frame(width: 18)

            Text(link.role?.fullDescription ?? "Unassigned role")
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Picker("", selection: Binding(
                get: { link.strictness },
                set: { link.strictness = $0 }
            )) {
                ForEach(RubricStrictness.allCases, id: \.self) { value in
                    Label(value.label, systemImage: value.symbolName).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Button {
                removeRoleLink(link)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func addRoleLink(role: InterviewRole) {
        let nextOrder = (rubric.roleLinks.map(\.sortOrder).max() ?? -1) + 1
        let link = RoleRubricLink(
            rubric: rubric,
            role: role,
            strictness: .standard,
            sortOrder: nextOrder
        )
        modelContext.insert(link)
        rubric.roleLinks.append(link)
        // Mirror the first link to the legacy `role` field so older code
        // paths (and the phase planner's fallback) keep finding it.
        if rubric.role == nil {
            rubric.role = role
        }
    }

    private func removeRoleLink(_ link: RoleRubricLink) {
        rubric.roleLinks.removeAll { $0.id == link.id }
        modelContext.delete(link)
        // Keep the legacy `role` field aligned with the first remaining link.
        rubric.role = rubric.roleLinks.sorted { $0.sortOrder < $1.sortOrder }.first?.role
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
