import SwiftUI
import SwiftData

/// Detail view for an `InterviewTemplate`. Mirrors `RubricEditorView` —
/// header (name/icon/description) → role scope section → phases list with
/// drag-to-reorder → add-phase menu. Edits autosave through SwiftData.
struct TemplateEditorView: View {
    @Bindable var template: InterviewTemplate
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]
    @Query(sort: \Rubric.createdAt, order: .reverse) private var allRubrics: [Rubric]

    private var activeRubrics: [Rubric] {
        allRubrics.filter { !$0.isArchived }
    }

    private var sortedPhases: [InterviewTemplatePhase] {
        template.phases.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedRoleLinks: [TemplateRoleLink] {
        template.roleLinks.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var unlinkedRoles: [InterviewRole] {
        let linked = Set(template.roleLinks.compactMap(\.role?.id))
        return roles.filter { !linked.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            EntityHeaderView(
                name: $template.name,
                description: Binding(
                    get: { template.templateDescription ?? "" },
                    set: {
                        template.templateDescription = $0.isEmpty ? nil : $0
                        template.updatedAt = .now
                    }
                ),
                iconName: Binding(
                    get: { template.iconName ?? "" },
                    set: {
                        template.iconName = $0.isEmpty ? nil : $0
                        template.updatedAt = .now
                    }
                ),
                iconFallback: "list.bullet.rectangle",
                tint: .cyan,
                namePrompt: "Untitled Template"
            )
            templateMetaStrip
            list
        }
        .navigationTitle(template.name.isEmpty ? "Untitled Template" : template.name)
    }

    /// Light row under the hero: phase count + total minutes + scored
    /// count. Refreshes from the live phase list on every render. Keeps
    /// "shape of the loop" visible without scrolling to the Phases
    /// section.
    private var templateMetaStrip: some View {
        let phases = sortedPhases
        let totalMinutes = phases.compactMap(\.targetMinutes).reduce(0, +)
        let scoredCount = phases.filter { $0.kind == .scored }.count
        return HStack(spacing: 12) {
            Label("\(phases.count) phase\(phases.count == 1 ? "" : "s")", systemImage: "list.bullet")
                .font(.caption)
                .foregroundStyle(.secondary)
            if scoredCount > 0 {
                Label("\(scoredCount) scored", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if totalMinutes > 0 {
                Label("~\(totalMinutes) min total", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar.opacity(0.4))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    private var list: some View {
        List {
            Section {
                Toggle("Available for any role", isOn: $template.appliesToAnyRole)
                if !template.appliesToAnyRole {
                    if sortedRoleLinks.isEmpty {
                        Text("Not linked to any role yet — link a role below to surface this template by default in the new-interview modal for that role.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedRoleLinks) { link in
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
                }
            } header: {
                Text("Applies To")
            } footer: {
                Text("\"Any role\" makes this template a default suggestion for every candidate. Otherwise, link the specific roles where this loop is the recommended starting point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(sortedPhases) { phase in
                    TemplatePhaseRow(
                        phase: phase,
                        availableRubrics: activeRubrics,
                        onDelete: { delete(phase) }
                    )
                }
                .onMove(perform: movePhases)

                Menu {
                    Button {
                        addPhase(kind: .scored, title: "New Phase")
                    } label: {
                        Label("Scored Phase", systemImage: "list.clipboard")
                    }
                    Button {
                        addPhase(kind: .unscored, title: "Discussion")
                    } label: {
                        Label("Unscored Discussion", systemImage: "bubble.left.and.bubble.right")
                    }
                    Divider()
                    Button {
                        addPhase(kind: .intro, title: "Intro")
                    } label: {
                        Label("Intro", systemImage: "person.wave.2")
                    }
                    Button {
                        addPhase(kind: .conclusion, title: "Conclusion")
                    } label: {
                        Label("Conclusion", systemImage: "questionmark.bubble")
                    }
                } label: {
                    Label("Add Phase", systemImage: "plus.circle")
                }
            } header: {
                Text("Phases")
            } footer: {
                Text("Phases run in order. Drag rows to reorder. Scored phases need a rubric — pick one inline, or leave blank to fill in at scheduling time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Role link row

    @ViewBuilder
    private func roleLinkRow(_ link: TemplateRoleLink) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.rectangle")
                .foregroundStyle(.cyan)
                .frame(width: 18)
            Text(link.role?.fullDescription ?? "Unassigned role")
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                template.roleLinks.removeAll { $0.id == link.id }
                modelContext.delete(link)
                template.updatedAt = .now
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func addRoleLink(role: InterviewRole) {
        let nextOrder = (template.roleLinks.map(\.sortOrder).max() ?? -1) + 1
        let link = TemplateRoleLink(template: template, role: role, sortOrder: nextOrder)
        modelContext.insert(link)
        template.roleLinks.append(link)
        template.updatedAt = .now
    }

    // MARK: - Phase mutations

    private func addPhase(kind: InterviewTemplatePhaseKind, title: String) {
        let nextOrder = (template.phases.map(\.sortOrder).max() ?? -1) + 1
        let phase = InterviewTemplatePhase(
            title: title,
            kind: kind,
            sortOrder: nextOrder
        )
        phase.template = template
        template.phases.append(phase)
        template.updatedAt = .now
    }

    private func delete(_ phase: InterviewTemplatePhase) {
        template.phases.removeAll { $0.id == phase.id }
        modelContext.delete(phase)
        renumberPhases()
        template.updatedAt = .now
    }

    private func movePhases(from source: IndexSet, to destination: Int) {
        var ordered = sortedPhases
        ordered.move(fromOffsets: source, toOffset: destination)
        for (idx, phase) in ordered.enumerated() {
            phase.sortOrder = idx
        }
        template.updatedAt = .now
    }

    private func renumberPhases() {
        for (idx, phase) in sortedPhases.enumerated() {
            phase.sortOrder = idx
        }
    }
}

// MARK: - Phase row

/// Editable row for one `InterviewTemplatePhase`. Layout: drag grip, icon
/// menu, title field, kind/rubric controls, target-minute stepper, delete.
struct TemplatePhaseRow: View {
    @Bindable var phase: InterviewTemplatePhase
    let availableRubrics: [Rubric]
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .help("Drag to reorder")

                PhaseIconMenu(
                    current: phase.resolvedIconName,
                    tint: phase.kind == .scored ? .cyan : .secondary
                ) { sym in
                    phase.iconName = sym
                }
                .help("Pick icon")

                TextField("Phase title", text: $phase.title)
                    .textFieldStyle(.plain)

                kindBadge

                Button { onDelete() } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove phase")
            }

            if phase.kind == .scored {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 22)
                    Picker("Rubric", selection: Binding(
                        get: { phase.rubric?.id },
                        set: { newID in
                            phase.rubric = availableRubrics.first { $0.id == newID }
                        }
                    )) {
                        Text("Pick at scheduling").tag(nil as UUID?)
                        ForEach(availableRubrics) { rubric in
                            Text(rubric.name).tag(rubric.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
                Toggle("Time box", isOn: Binding(
                    get: { phase.targetMinutes != nil },
                    set: { phase.targetMinutes = $0 ? (phase.targetMinutes ?? 30) : nil }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                if phase.targetMinutes != nil {
                    Stepper(
                        "\(phase.targetMinutes ?? 30) min",
                        value: Binding(
                            get: { phase.targetMinutes ?? 30 },
                            set: { phase.targetMinutes = max($0, 1) }
                        ),
                        in: 5...240,
                        step: 5
                    )
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var kindBadge: some View {
        let label: String = switch phase.kind {
        case .intro: "Intro"
        case .scored: "Scored"
        case .unscored: "Discussion"
        case .conclusion: "Wrap"
        }
        let color: Color = switch phase.kind {
        case .scored: .cyan
        case .intro, .conclusion: .secondary
        case .unscored: .blue
        }
        Menu {
            ForEach([InterviewTemplatePhaseKind.intro, .scored, .unscored, .conclusion], id: \.self) { kind in
                Button {
                    phase.kind = kind
                    if kind != .scored { phase.rubric = nil }
                } label: {
                    Text(humanLabel(for: kind))
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Phase kind")
    }

    private func humanLabel(for kind: InterviewTemplatePhaseKind) -> String {
        switch kind {
        case .intro: "Intro (unscored)"
        case .scored: "Scored phase"
        case .unscored: "Unscored discussion"
        case .conclusion: "Conclusion (unscored)"
        }
    }
}
