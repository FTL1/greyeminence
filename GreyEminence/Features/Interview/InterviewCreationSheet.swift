import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - View Model

/// State for the interview-creation modal. Owns the candidate selection,
/// the chosen template (if any), the editable phase list, and pre-notes.
/// Lives for the lifetime of the sheet — discarded on cancel; flushes
/// into a new `Interview` on schedule.
@Observable
@MainActor
final class InterviewCreationViewModel {
    var selectedCandidate: Candidate?
    var selectedTemplate: InterviewTemplate?
    /// Editable plan in the right pane. Built from the chosen template's
    /// phases at template-select time, then mutated freely.
    var editablePhases: [PlannedPhase] = []
    var selectedInterviewers: Set<UUID> = []
    var preNotes: String = ""

    /// Role at the moment the template was chosen — kept as a snapshot
    /// (not derivable from `selectedTemplate`) so the role-change banner
    /// can detect a candidate-role shift without overwriting the user's
    /// in-progress edits.
    var roleAtTemplateSelection: UUID?

    var canSchedule: Bool {
        selectedCandidate != nil && hasScoredPhase
    }

    var hasScoredPhase: Bool {
        editablePhases.contains { $0.rubric != nil }
    }

    /// True when the active candidate's role has shifted away from the
    /// role that drove the current template recommendation, so the modal
    /// can surface a banner offering to re-suggest. False if no template
    /// is selected or no candidate is selected.
    var candidateRoleChangedSinceTemplate: Bool {
        guard let templateRole = roleAtTemplateSelection,
              let candidate = selectedCandidate,
              let currentRole = candidate.role else { return false }
        return templateRole != currentRole.id
    }

    /// Adopt a template into the editable phase list. Replaces the
    /// current phases — caller is responsible for confirming if the user
    /// has unsaved edits. `nil` = blank plan with intro/conclusion.
    func adoptTemplate(_ template: InterviewTemplate?) {
        selectedTemplate = template
        roleAtTemplateSelection = selectedCandidate?.role?.id
        guard let template else {
            editablePhases = [.intro(), .conclusion()]
            return
        }
        editablePhases = template.orderedPhases.map(PlannedPhase.from(templatePhase:))
    }

    func appendPhase(_ phase: PlannedPhase) {
        editablePhases.append(phase)
    }

    func removePhase(at index: Int) {
        guard editablePhases.indices.contains(index) else { return }
        editablePhases.remove(at: index)
    }

    func movePhases(from source: IndexSet, to destination: Int) {
        editablePhases.move(fromOffsets: source, toOffset: destination)
    }

    /// Persist the planned interview as `.scheduled`. Bumps the
    /// originating template's usage stats. Returns the created Interview
    /// so the caller can navigate to its scorecard.
    @discardableResult
    func schedule(
        in modelContext: ModelContext,
        interviewers contacts: [Contact],
        recordingVM: InterviewRecordingViewModel
    ) -> Interview? {
        guard let candidate = selectedCandidate else { return nil }
        let interview = recordingVM.scheduleInterview(
            candidate: candidate,
            plannedPhases: editablePhases,
            interviewers: contacts,
            notes: preNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : preNotes,
            in: modelContext
        )
        if let template = selectedTemplate {
            interview.template = template
            interview.templateNameAtSchedule = template.name
            template.lastUsedAt = .now
            template.usageCount += 1
            template.updatedAt = .now
        }
        return interview
    }
}

// MARK: - Sheet

/// Modal launched from the Interviews tab "+" button. Two-pane layout:
/// templates + role-linked rubrics on the left, editable phase list on
/// the right. Header carries candidate picker + past-interview summary.
/// Footer is the Schedule CTA.
struct InterviewCreationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var interviewViewModel: InterviewRecordingViewModel
    /// Called after a successful schedule with the new Interview. Lets the
    /// parent select it in the list and navigate to its scorecard.
    var onScheduled: (Interview) -> Void

    @State private var vm = InterviewCreationViewModel()
    @State private var showAddCandidate = false

    @Query(sort: \Candidate.name) private var allCandidates: [Candidate]
    @Query(
        sort: [
            SortDescriptor(\InterviewTemplate.lastUsedAt, order: .reverse),
            SortDescriptor(\InterviewTemplate.name)
        ]
    ) private var allTemplates: [InterviewTemplate]
    @Query(sort: \Rubric.createdAt, order: .reverse) private var allRubrics: [Rubric]
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    private var activeCandidates: [Candidate] {
        allCandidates.filter { !$0.isArchived }
    }

    private var activeInterviewers: [Contact] {
        allContacts.filter { !$0.isArchived && $0.isInterviewer }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.candidateRoleChangedSinceTemplate {
                roleChangeBanner
                Divider()
            }
            HStack(spacing: 0) {
                templateRail
                    .frame(width: 280)
                Divider()
                phaseEditor
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 640, idealHeight: 720)
        .sheet(isPresented: $showAddCandidate) {
            AddCandidateSheet()
        }
        .onAppear {
            if vm.editablePhases.isEmpty {
                vm.adoptTemplate(nil)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.shield.checkmark")
                    .foregroundStyle(.cyan)
                    .font(.title3)
                Text("New Interview")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Text("Candidate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $vm.selectedCandidate) {
                    Text("Select a candidate…").tag(nil as Candidate?)
                    ForEach(activeCandidates) { candidate in
                        Text(candidateLabel(candidate)).tag(candidate as Candidate?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                Button {
                    showAddCandidate = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add a new candidate")

                if let candidate = vm.selectedCandidate, let role = candidate.role {
                    Text("· \(role.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let candidate = vm.selectedCandidate {
                    pastInterviewsSummary(for: candidate)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func candidateLabel(_ candidate: Candidate) -> String {
        guard let role = candidate.role else { return candidate.name }
        return "\(candidate.name)  ·  \(role.displayTitle)"
    }

    @ViewBuilder
    private func pastInterviewsSummary(for candidate: Candidate) -> some View {
        let past = candidate.interviews
            .filter { $0.status == .completed || $0.status == .archived }
            .sorted { $0.createdAt > $1.createdAt }
        if past.isEmpty {
            Text("No prior interviews")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(past.count) past")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let last = past.first {
                    Text("· last \(last.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .help(past.map {
                let date = $0.createdAt.formatted(date: .abbreviated, time: .omitted)
                let label = $0.templateNameAtSchedule ?? $0.rubric?.name ?? "Interview"
                return "\(date) — \(label)"
            }.joined(separator: "\n"))
        }
    }

    // MARK: Role-change banner

    private var roleChangeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Candidate role changed since the template was selected. The phase plan was kept as-is — pick a different template if you'd like to start from a recommended one for the new role.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Re-suggest") {
                vm.adoptTemplate(suggestedTemplate)
            }
            .controlSize(.small)
            .disabled(suggestedTemplate == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.08))
    }

    /// First template that applies to the candidate's current role, or
    /// the first universal template, or nil.
    private var suggestedTemplate: InterviewTemplate? {
        guard let role = vm.selectedCandidate?.role else { return nil }
        let active = allTemplates.filter { !$0.isArchived }
        return active.first(where: { $0.appliesTo(role: role) }) ?? active.first(where: { $0.appliesToAnyRole })
    }

    // MARK: Template Rail

    private var templateRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !recentTemplates.isEmpty {
                        railSection("Recent") {
                            ForEach(recentTemplates) { template in
                                templateRailRow(template)
                            }
                        }
                    }

                    railSection("Templates") {
                        ForEach(visibleTemplates) { template in
                            templateRailRow(template)
                        }
                        blankPlanRow
                    }

                    railSection("Role-linked rubrics") {
                        if let role = vm.selectedCandidate?.role {
                            let used = usedRubricIDs
                            let rubrics = roleScopedRubrics(role: role).filter { !used.contains($0.id) }
                            if rubrics.isEmpty {
                                Text("No additional rubrics linked to \(role.displayTitle).")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                            } else {
                                ForEach(rubrics) { rubric in
                                    rubricRailRow(rubric)
                                }
                            }
                        } else {
                            Text("Pick a candidate to see role-linked rubrics here.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color.secondary.opacity(0.04))
    }

    private func railSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            content()
                .padding(.horizontal, 8)
        }
    }

    private var visibleTemplates: [InterviewTemplate] {
        allTemplates.filter { !$0.isArchived }
    }

    /// Top 3 templates by lastUsedAt that match the candidate's role
    /// (or universal). Hidden when no candidate is picked or list is empty.
    private var recentTemplates: [InterviewTemplate] {
        guard let role = vm.selectedCandidate?.role else { return [] }
        return visibleTemplates
            .filter { $0.lastUsedAt != nil && ($0.appliesToAnyRole || $0.appliesTo(role: role)) }
            .prefix(3)
            .map { $0 }
    }

    private func roleScopedRubrics(role: InterviewRole) -> [Rubric] {
        allRubrics.filter { !$0.isArchived && $0.appliesTo(role: role) }
    }

    private var usedRubricIDs: Set<UUID> {
        Set(vm.editablePhases.compactMap { $0.rubric?.id })
    }

    private func templateRailRow(_ template: InterviewTemplate) -> some View {
        let isSelected = vm.selectedTemplate?.id == template.id
        return Button {
            vm.adoptTemplate(template)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: template.iconName ?? "list.bullet.rectangle")
                    .foregroundStyle(isSelected ? .white : .cyan)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? Color.cyan : Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let desc = template.templateDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("\(template.phases.count) phases")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(isSelected ? Color.cyan.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var blankPlanRow: some View {
        let isSelected = vm.selectedTemplate == nil
        return Button {
            vm.adoptTemplate(nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Blank plan")
                        .font(.caption.weight(.semibold))
                    Text("Intro + Conclusion only — build it from scratch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(isSelected ? Color.cyan.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rubricRailRow(_ rubric: Rubric) -> some View {
        Button {
            vm.appendPhase(.from(rubric: rubric))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                Text(rubric.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "plus")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drag-out support — drop this rubric onto the phase pane to
        // insert as a phase. Payload is the rubric UUID string.
        .draggable(rubric.id.uuidString) {
            HStack(spacing: 4) {
                Image(systemName: "list.clipboard")
                Text(rubric.name).font(.caption)
            }
            .padding(6)
            .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: Phase Editor (right pane)

    private var phaseEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                phaseListHeader
                phaseList
                interviewersSection
                preNotesSection
            }
            .padding(16)
        }
    }

    private var phaseListHeader: some View {
        HStack {
            Text("Phases")
                .font(.subheadline.weight(.semibold))
            if let template = vm.selectedTemplate {
                Text("from \(template.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(scoredPhasesSummary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var scoredPhasesSummary: String {
        let scored = vm.editablePhases.filter { $0.rubric != nil }.count
        let total = vm.editablePhases.count
        let totalMinutes = vm.editablePhases.compactMap(\.targetMinutes).reduce(0, +)
        if totalMinutes > 0 {
            return "\(scored) scored · \(total) total · ~\(totalMinutes) min"
        }
        return "\(scored) scored · \(total) total"
    }

    private var phaseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.editablePhases.indices, id: \.self) { idx in
                PlannedPhaseRow(
                    phase: vm.editablePhases[idx],
                    availableRubrics: allRubrics.filter { !$0.isArchived },
                    onUpdate: { updated in
                        vm.editablePhases[idx] = updated
                    },
                    onDelete: {
                        vm.removePhase(at: idx)
                    }
                )
            }
            addPhaseMenu
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        // Drop target for rubrics dragged from the rail.
        .dropDestination(for: String.self) { items, _ in
            let used = usedRubricIDs
            var didAccept = false
            for str in items {
                guard let id = UUID(uuidString: str), !used.contains(id) else { continue }
                if let rubric = allRubrics.first(where: { $0.id == id }) {
                    vm.appendPhase(.from(rubric: rubric))
                    didAccept = true
                }
            }
            return didAccept
        }
    }

    private var addPhaseMenu: some View {
        Menu {
            if let role = vm.selectedCandidate?.role {
                let used = usedRubricIDs
                let unused = roleScopedRubrics(role: role).filter { !used.contains($0.id) }
                if !unused.isEmpty {
                    Section("From this role") {
                        ForEach(unused) { rubric in
                            Button(rubric.name) {
                                vm.appendPhase(.from(rubric: rubric))
                            }
                        }
                    }
                }
            }
            let allActive = allRubrics.filter { !$0.isArchived }
            if !allActive.isEmpty {
                Section("From all rubrics") {
                    ForEach(allActive) { rubric in
                        Button(rubric.name) {
                            vm.appendPhase(.from(rubric: rubric))
                        }
                    }
                }
            }
            Divider()
            Button("Unscored Discussion") {
                vm.appendPhase(PlannedPhase(title: "Discussion", rubric: nil, iconName: "bubble.left.and.bubble.right"))
            }
        } label: {
            Label("Add phase", systemImage: "plus.circle")
                .font(.caption)
        }
    }

    private var interviewersSection: some View {
        DisclosureGroup {
            if activeInterviewers.isEmpty {
                Text("No interviewers configured. Mark contacts as interviewers in People.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeInterviewers) { contact in
                        Toggle(isOn: Binding(
                            get: { vm.selectedInterviewers.contains(contact.id) },
                            set: { isOn in
                                if isOn {
                                    vm.selectedInterviewers.insert(contact.id)
                                } else {
                                    vm.selectedInterviewers.remove(contact.id)
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(contact.initials)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(contact.avatarColor.gradient, in: Circle())
                                Text(contact.name)
                                    .font(.caption)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Co-interviewers")
                    .font(.caption.weight(.semibold))
                if !vm.selectedInterviewers.isEmpty {
                    Text("(\(vm.selectedInterviewers.count) selected)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var preNotesSection: some View {
        DisclosureGroup {
            TextEditor(text: $vm.preNotes)
                .frame(minHeight: 60)
                .font(.caption)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )
        } label: {
            Text("Pre-interview notes")
                .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            statusLabel
            Spacer()
            Button {
                schedule()
            } label: {
                Label("Schedule", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .controlSize(.large)
            .disabled(!vm.canSchedule)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if vm.selectedCandidate == nil {
            Text("Pick a candidate to schedule")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !vm.hasScoredPhase {
            Text("Add at least one scored phase")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("Ready — \(vm.editablePhases.count) phase\(vm.editablePhases.count == 1 ? "" : "s"), \(vm.editablePhases.filter { $0.rubric != nil }.count) scored")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func schedule() {
        let chosenContacts = activeInterviewers.filter { vm.selectedInterviewers.contains($0.id) }
        guard let interview = vm.schedule(
            in: modelContext,
            interviewers: chosenContacts,
            recordingVM: interviewViewModel
        ) else { return }
        onScheduled(interview)
        dismiss()
    }
}

// MARK: - Planned phase row

/// One row in the modal's phase pane. Operates on a `PlannedPhase` value
/// type via an onUpdate callback rather than a binding because
/// PlannedPhase is a struct that doesn't survive binding-into-array
/// with consistent identity.
struct PlannedPhaseRow: View {
    var phase: PlannedPhase
    let availableRubrics: [Rubric]
    var onUpdate: (PlannedPhase) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .help("Drag to reorder")

            PhaseIconMenu(
                current: phase.resolvedIconName,
                tint: phase.rubric != nil ? .cyan : .secondary
            ) { sym in
                var copy = phase
                copy.iconName = sym
                onUpdate(copy)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Phase title", text: Binding(
                        get: { phase.title },
                        set: {
                            var copy = phase
                            copy.title = $0
                            onUpdate(copy)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.body)

                    if phase.sourceTemplatePhaseID != nil {
                        Text("Template")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.cyan.opacity(0.15), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                }

                if !availableRubrics.isEmpty {
                    Picker("Rubric", selection: Binding(
                        get: { phase.rubric?.id },
                        set: { newID in
                            var copy = phase
                            copy.rubric = availableRubrics.first { $0.id == newID }
                            onUpdate(copy)
                        }
                    )) {
                        Text("(unscored)").tag(nil as UUID?)
                        ForEach(availableRubrics) { rubric in
                            Text(rubric.name).tag(rubric.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Remove phase")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

