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
    /// Planned slot. Defaults to the top of the next hour so the user
    /// usually only needs to confirm.
    var scheduledAt: Date = InterviewCreationViewModel.defaultScheduledAt()

    private static func defaultScheduledAt() -> Date {
        let cal = Calendar.current
        let now = Date()
        let oneHourLater = cal.date(byAdding: .hour, value: 1, to: now) ?? now
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: oneHourLater)
        return cal.date(from: comps) ?? oneHourLater
    }

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

    /// Insert a phase at a specific index, clamped to the array bounds.
    /// Used by per-row drop targets so dragging onto a row inserts
    /// before that row instead of always appending.
    func insertPhase(_ phase: PlannedPhase, at index: Int) {
        let clamped = max(0, min(index, editablePhases.count))
        editablePhases.insert(phase, at: clamped)
    }

    func removePhase(at index: Int) {
        guard editablePhases.indices.contains(index) else { return }
        editablePhases.remove(at: index)
    }

    func movePhases(from source: IndexSet, to destination: Int) {
        editablePhases.move(fromOffsets: source, toOffset: destination)
    }

    /// Diff state of the editable plan vs. the originating template.
    /// Drives the "Template ▾" footer menu — what's offered changes
    /// based on whether the user has diverged from the spine.
    enum TemplateDiffState {
        /// No template adopted (blank plan). Only "Save as new template…"
        /// is offered.
        case noTemplate
        /// Plan exactly matches the originating template. Offers
        /// "Duplicate as new template…" only — the in-place save is a
        /// no-op.
        case matches(InterviewTemplate)
        /// Plan diverges from the originating template. Offers
        /// "Update <name>", "Save as new template…", and "Revert".
        case diverges(InterviewTemplate)
    }

    var templateDiffState: TemplateDiffState {
        guard let template = selectedTemplate else { return .noTemplate }
        return phasesMatch(template) ? .matches(template) : .diverges(template)
    }

    /// True when every editable phase corresponds 1:1 (in order, by id +
    /// content) to the template's persisted phases. Any structural
    /// change — added phase, removed phase, reorder, retitle, rubric
    /// swap, icon change, time-box change — flips this to false.
    private func phasesMatch(_ template: InterviewTemplate) -> Bool {
        let templatePhases = template.orderedPhases
        guard templatePhases.count == editablePhases.count else { return false }
        for (tp, ep) in zip(templatePhases, editablePhases) {
            if ep.sourceTemplatePhaseID != tp.id { return false }
            if ep.title != tp.title { return false }
            if ep.rubric?.id != tp.rubric?.id { return false }
            if ep.iconName != tp.iconName { return false }
            if ep.targetMinutes != tp.targetMinutes { return false }
            if ep.kind != tp.kind { return false }
        }
        return true
    }

    /// Wipe the originating template's phases and replace them with the
    /// current editable plan. Cascade delete on the relationship clears
    /// the old phases; new ones get fresh `id`s, then `editablePhases`
    /// is re-pointed at those fresh ids so the diff state flips back to
    /// `.matches`.
    func updateOriginatingTemplate(in modelContext: ModelContext) {
        guard let template = selectedTemplate else { return }
        for phase in template.phases {
            modelContext.delete(phase)
        }
        template.phases.removeAll()
        var newSourceIDs: [UUID] = []
        for (idx, planned) in editablePhases.enumerated() {
            let phase = InterviewTemplatePhase(
                title: planned.title,
                kind: planned.resolvedKind,
                rubric: planned.rubric,
                sortOrder: idx,
                iconName: planned.iconName,
                targetMinutes: planned.targetMinutes
            )
            phase.template = template
            template.phases.append(phase)
            newSourceIDs.append(phase.id)
        }
        template.updatedAt = .now
        // Re-point editable phases at the freshly-saved template phase
        // ids so the diff flips back to .matches without forcing a
        // reload of the modal.
        for (idx, newID) in newSourceIDs.enumerated() where idx < editablePhases.count {
            editablePhases[idx].sourceTemplatePhaseID = newID
        }
    }

    /// Create a brand-new `InterviewTemplate` from the current editable
    /// plan, optionally scoping it to roles. The new template becomes
    /// the selected one so subsequent saves go to it. Returns the new
    /// template so the caller can show it in the library.
    @discardableResult
    func saveAsNewTemplate(
        name: String,
        description: String?,
        appliesToAnyRole: Bool,
        scopedRoles: [InterviewRole],
        in modelContext: ModelContext
    ) -> InterviewTemplate {
        let template = InterviewTemplate(
            name: name,
            templateDescription: description,
            iconName: nil,
            appliesToAnyRole: appliesToAnyRole
        )
        modelContext.insert(template)
        var newSourceIDs: [UUID] = []
        for (idx, planned) in editablePhases.enumerated() {
            let phase = InterviewTemplatePhase(
                title: planned.title,
                kind: planned.resolvedKind,
                rubric: planned.rubric,
                sortOrder: idx,
                iconName: planned.iconName,
                targetMinutes: planned.targetMinutes
            )
            phase.template = template
            template.phases.append(phase)
            newSourceIDs.append(phase.id)
        }
        if !appliesToAnyRole {
            for (idx, role) in scopedRoles.enumerated() {
                let link = TemplateRoleLink(template: template, role: role, sortOrder: idx)
                modelContext.insert(link)
                template.roleLinks.append(link)
            }
        }
        selectedTemplate = template
        roleAtTemplateSelection = selectedCandidate?.role?.id
        for (idx, newID) in newSourceIDs.enumerated() where idx < editablePhases.count {
            editablePhases[idx].sourceTemplatePhaseID = newID
        }
        return template
    }

    /// Discard local edits and re-adopt the originating template's
    /// current persisted phases. No-op if no template is selected.
    func revertToOriginatingTemplate() {
        guard let template = selectedTemplate else { return }
        adoptTemplate(template)
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
            scheduledAt: scheduledAt,
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
    /// Optionally pre-select a candidate when the sheet opens. Useful for
    /// "Schedule Interview" launched from a candidate's detail page.
    var presetCandidate: Candidate? = nil
    /// Called after a successful schedule with the new Interview. Lets the
    /// parent select it in the list and navigate to its scorecard.
    var onScheduled: (Interview) -> Void

    @State private var vm = InterviewCreationViewModel()
    @State private var showAddCandidate = false
    @State private var showSaveTemplate = false

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
            if let presetCandidate, vm.selectedCandidate == nil {
                vm.selectedCandidate = presetCandidate
            }
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
        let panel = activeInterviewers.filter { vm.selectedInterviewers.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.editablePhases.indices, id: \.self) { idx in
                PlannedPhaseRow(
                    phase: vm.editablePhases[idx],
                    availableRubrics: allRubrics.filter { !$0.isArchived },
                    panelInterviewers: panel,
                    onUpdate: { updated in
                        vm.editablePhases[idx] = updated
                    },
                    onDelete: {
                        vm.removePhase(at: idx)
                    }
                )
                .dropDestination(for: String.self) { items, _ in
                    insertDroppedRubrics(items, at: idx)
                }
            }
            addPhaseMenu
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        // Pane-level drop target — fallback when the user drops in the
        // gutter between rows or below the last one. Per-row destinations
        // above take precedence and insert at that index.
        .dropDestination(for: String.self) { items, _ in
            insertDroppedRubrics(items, at: vm.editablePhases.count)
        }
    }

    /// Resolve dragged rubric-id strings to Rubric records, skip
    /// duplicates already in the plan, and insert each at `index`.
    /// Returns true if any rubric actually landed so SwiftUI's drop
    /// animation reflects whether the gesture did anything.
    private func insertDroppedRubrics(_ items: [String], at index: Int) -> Bool {
        let used = usedRubricIDs
        var insertAt = index
        var didAccept = false
        for str in items {
            guard let id = UUID(uuidString: str), !used.contains(id) else { continue }
            guard let rubric = allRubrics.first(where: { $0.id == id }) else { continue }
            vm.insertPhase(.from(rubric: rubric), at: insertAt)
            insertAt += 1
            didAccept = true
        }
        return didAccept
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
        HStack(spacing: 12) {
            statusLabel
            Spacer()
            scheduledForPicker
            templateActionsMenu
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
        .sheet(isPresented: $showSaveTemplate) {
            SaveTemplateSheet(
                suggestedRole: vm.selectedCandidate?.role,
                onSave: { name, description, anyRole, roles in
                    vm.saveAsNewTemplate(
                        name: name,
                        description: description,
                        appliesToAnyRole: anyRole,
                        scopedRoles: roles,
                        in: modelContext
                    )
                }
            )
        }
    }

    /// "Template ▾" menu in the footer. Items adapt to the diff state:
    /// in-place save vs. save-as-new vs. duplicate-only vs. revert. Only
    /// rendered when the plan has at least one phase to save.
    @ViewBuilder
    private var templateActionsMenu: some View {
        if !vm.editablePhases.isEmpty {
            Menu {
                switch vm.templateDiffState {
                case .noTemplate:
                    Button("Save as new template…") { showSaveTemplate = true }
                case .matches(_):
                    Text("Saved")
                    Divider()
                    Button("Duplicate as new template…") { showSaveTemplate = true }
                case .diverges(let template):
                    Button("Update '\(template.name)'") {
                        vm.updateOriginatingTemplate(in: modelContext)
                    }
                    Button("Save as new template…") { showSaveTemplate = true }
                    Divider()
                    Button("Revert to template", role: .destructive) {
                        vm.revertToOriginatingTemplate()
                    }
                }
            } label: {
                Label(templateMenuLabel, systemImage: "list.bullet.rectangle")
                    .font(.caption)
            }
            .controlSize(.small)
            .help("Save edits to the originating template, or save the current plan as a new template.")
        }
    }

    private var templateMenuLabel: String {
        switch vm.templateDiffState {
        case .noTemplate: "Template"
        case .matches: "Template ✓"
        case .diverges: "Template •"
        }
    }

    private var scheduledForPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Scheduled for")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                "",
                selection: $vm.scheduledAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08), in: Capsule())
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
    /// Interviewers the user has selected at the interview level — the
    /// pool from which a phase's owners can be drawn. Filtering here
    /// (vs all contacts) keeps the menu short and forces the panel
    /// decision to happen once at the top.
    let panelInterviewers: [Contact]
    var onUpdate: (PlannedPhase) -> Void
    var onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showQuickCreateRubric = false
    @State private var quickRubricName: String = ""

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

                rubricMenu
                ownersChips
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
        .sheet(isPresented: $showQuickCreateRubric) {
            quickCreateRubricSheet
        }
    }

    /// Rubric picker as a Menu (instead of Picker) so we can mix in a
    /// "+ New rubric…" action item at the bottom for inline creation.
    @ViewBuilder
    private var rubricMenu: some View {
        Menu {
            Button("(unscored)") {
                var copy = phase
                copy.rubric = nil
                onUpdate(copy)
            }
            if !availableRubrics.isEmpty {
                Divider()
                ForEach(availableRubrics) { rubric in
                    Button(rubric.name) {
                        var copy = phase
                        copy.rubric = rubric
                        onUpdate(copy)
                    }
                }
            }
            Divider()
            Button {
                quickRubricName = phase.title.trimmingCharacters(in: .whitespacesAndNewlines)
                showQuickCreateRubric = true
            } label: {
                Label("New rubric…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text(phase.rubric?.name ?? "(unscored)")
                    .font(.caption)
                    .foregroundStyle(phase.rubric == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Inline rubric quick-create. Minimal — name only. The user can flesh
    /// out sections later in the Rubrics tab. New rubric is auto-selected
    /// for this phase on create.
    private var quickCreateRubricSheet: some View {
        VStack(spacing: 0) {
            Text("New Rubric")
                .font(.headline)
                .padding()
            Form {
                TextField("Name", text: $quickRubricName, prompt: Text("Rubric name"))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 90)
            HStack {
                Button("Cancel") { showQuickCreateRubric = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    createRubric()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(quickRubricName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 360)
    }

    /// Compact chip strip showing assigned owners' initials with a Menu
    /// to toggle each panel member on/off for this phase. Hidden when
    /// the panel is empty — phase owners are a *narrowing* of the panel,
    /// pointless before the user picks any panel members.
    @ViewBuilder
    private var ownersChips: some View {
        if !panelInterviewers.isEmpty {
            Menu {
                ForEach(panelInterviewers) { contact in
                    Button {
                        toggleOwner(contact)
                    } label: {
                        if phase.assignedInterviewerIDs.contains(contact.id) {
                            Label(contact.name, systemImage: "checkmark")
                        } else {
                            Text(contact.name)
                        }
                    }
                }
                if !phase.assignedInterviewerIDs.isEmpty {
                    Divider()
                    Button("Clear owners") {
                        var copy = phase
                        copy.assignedInterviewerIDs = []
                        onUpdate(copy)
                    }
                }
            } label: {
                let owners = panelInterviewers.filter { phase.assignedInterviewerIDs.contains($0.id) }
                HStack(spacing: -4) {
                    if owners.isEmpty {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    } else {
                        ForEach(owners.prefix(3)) { contact in
                            Text(contact.initials)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(contact.avatarColor.gradient, in: Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        }
                        if owners.count > 3 {
                            Text("+\(owners.count - 3)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(Color.secondary.opacity(0.2), in: Circle())
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(phase.assignedInterviewerIDs.isEmpty
                  ? "Assign phase owners (defaults to whole panel)"
                  : "Phase owners — \(panelInterviewers.filter { phase.assignedInterviewerIDs.contains($0.id) }.map(\.name).joined(separator: ", "))")
        }
    }

    private func toggleOwner(_ contact: Contact) {
        var copy = phase
        if copy.assignedInterviewerIDs.contains(contact.id) {
            copy.assignedInterviewerIDs.remove(contact.id)
        } else {
            copy.assignedInterviewerIDs.insert(contact.id)
        }
        onUpdate(copy)
    }

    private func createRubric() {
        let trimmed = quickRubricName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let rubric = Rubric(name: trimmed)
        modelContext.insert(rubric)
        var copy = phase
        copy.rubric = rubric
        onUpdate(copy)
        showQuickCreateRubric = false
    }
}

// MARK: - Save-as-new-template sheet

/// Stacked sheet for "Save as new template…". Asks for a name, optional
/// description, and role-scope (universal toggle + multi-pick of the
/// candidate's role plus any others). Defaults the role-scope to the
/// current candidate's role when set — the common case is "save the
/// loop I just built for senior backend so I can re-use it next time."
struct SaveTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InterviewRole.createdAt) private var allRoles: [InterviewRole]

    /// Candidate's role at sheet open, used to seed the default scope.
    let suggestedRole: InterviewRole?
    var onSave: (_ name: String, _ description: String?, _ appliesToAnyRole: Bool, _ scopedRoles: [InterviewRole]) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var appliesToAnyRole: Bool = false
    @State private var selectedRoleIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Text("Save as Template")
                .font(.headline)
                .padding()

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Backend Loop"))
                    TextField("Description (optional)", text: $description, prompt: Text("What this loop is for"), axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle("Available for any role", isOn: $appliesToAnyRole)
                    if !appliesToAnyRole {
                        if allRoles.isEmpty {
                            Text("No roles defined yet. Add roles in the Organization tab to scope this template.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(allRoles) { role in
                                Toggle(isOn: Binding(
                                    get: { selectedRoleIDs.contains(role.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedRoleIDs.insert(role.id)
                                        } else {
                                            selectedRoleIDs.remove(role.id)
                                        }
                                    }
                                )) {
                                    Text(role.fullDescription)
                                        .font(.caption)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                } header: {
                    Text("Applies to")
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 280, maxHeight: 360)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear {
            if let role = suggestedRole, selectedRoleIDs.isEmpty {
                selectedRoleIDs.insert(role.id)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let scopedRoles = appliesToAnyRole ? [] : allRoles.filter { selectedRoleIDs.contains($0.id) }
        onSave(
            trimmedName,
            trimmedDescription.isEmpty ? nil : trimmedDescription,
            appliesToAnyRole,
            scopedRoles
        )
        dismiss()
    }
}

