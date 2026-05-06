import SwiftUI
import SwiftData

struct InterviewSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Candidate.name) private var candidates: [Candidate]
    @Query(sort: \Rubric.createdAt, order: .reverse) private var rubrics: [Rubric]
    @Query(sort: \Contact.name) private var contacts: [Contact]

    var interviewViewModel: InterviewRecordingViewModel

    /// Titles we treat as "untouched defaults" — assigning a rubric to a
    /// phase whose title is one of these auto-renames it to the rubric.
    private static let placeholderTitles: Set<String> = ["", "Phase", "Discussion"]

    @State private var selectedCandidate: Candidate?
    @State private var plannedPhases: [PlannedPhase] = [.intro(), .conclusion()]
    @State private var selectedInterviewers: Set<UUID> = []
    @State private var preNotes: String = ""
    @State private var showAddCandidate = false

    private var activeCandidates: [Candidate] {
        candidates.filter { !$0.isArchived }
    }

    private var activeInterviewers: [Contact] {
        contacts.filter { !$0.isArchived && $0.isInterviewer }
    }

    private var activeRubrics: [Rubric] {
        rubrics.filter { !$0.isArchived }
    }

    /// Rubrics likely relevant to this candidate's role — used to seed
    /// suggestions and order the rubric picker. Reads through both the
    /// legacy `Rubric.role` pointer and the newer `roleLinks` join so
    /// the planner finds rubrics that apply to multiple roles.
    private var roleScopedRubrics: [Rubric] {
        guard let role = selectedCandidate?.role else { return activeRubrics }
        let matching = activeRubrics.filter { $0.appliesTo(role: role) }
        return matching.isEmpty ? activeRubrics : matching
    }

    /// At least one scored phase (with a rubric) is required to start —
    /// otherwise the AI loop will skip every cycle and the interview
    /// produces no scores.
    private var hasScoredPhase: Bool {
        plannedPhases.contains { $0.rubric != nil }
    }

    private var canStart: Bool {
        selectedCandidate != nil && hasScoredPhase
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.cyan)
                    Text("Interview Setup")
                        .font(.title2.weight(.semibold))
                    Text("Plan the phases you'll run through")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form
                Form {
                    Section("Candidate") {
                        HStack {
                            Picker("Candidate", selection: $selectedCandidate) {
                                Text("Select...").tag(nil as Candidate?)
                                ForEach(activeCandidates) { candidate in
                                    HStack {
                                        Text(candidate.name)
                                        if let role = candidate.role {
                                            Text("(\(role.displayTitle))")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(candidate as Candidate?)
                                }
                            }
                            Button {
                                showAddCandidate = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        if plannedPhases.isEmpty {
                            Text("No phases planned. Add one below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(plannedPhases.enumerated()), id: \.element.id) { index, phase in
                            phaseRow(at: index, phase: phase)
                        }
                        .onMove { source, destination in
                            plannedPhases.move(fromOffsets: source, toOffset: destination)
                        }

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(roleScopedRubrics) { rubric in
                                    Button(rubric.name) {
                                        plannedPhases.append(.from(rubric: rubric))
                                    }
                                }
                                if roleScopedRubrics.isEmpty {
                                    Text("No rubrics defined")
                                }
                            } label: {
                                Label("Add Rubric Phase", systemImage: "plus.rectangle.on.rectangle")
                            }
                            Button {
                                plannedPhases.append(PlannedPhase(title: "Discussion", rubric: nil))
                            } label: {
                                Label("Add Unscored", systemImage: "plus.bubble")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    } header: {
                        HStack {
                            Text("Planned Phases")
                            Spacer()
                            Button {
                                resetToRoleDefaults()
                            } label: {
                                Text("Defaults")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Replace with the default phase plan for this candidate's role")
                        }
                    } footer: {
                        Text("Phases run in order. The AI scores only during phases that have a rubric attached.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Section {
                        if activeInterviewers.isEmpty {
                            Text("No interviewers configured. Mark contacts as interviewers in People.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(activeInterviewers) { contact in
                                Toggle(isOn: Binding(
                                    get: { selectedInterviewers.contains(contact.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedInterviewers.insert(contact.id)
                                        } else {
                                            selectedInterviewers.remove(contact.id)
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
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    } header: {
                        Text("Other Interviewers")
                    } footer: {
                        Text("You are always included as an interviewer.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Section("Pre-Interview Notes") {
                        TextEditor(text: $preNotes)
                            .frame(minHeight: 50)
                    }
                }
                .formStyle(.grouped)
                .frame(maxWidth: 560, maxHeight: 600)

                // Start button
                Button {
                    startInterview()
                } label: {
                    Label("Start Interview", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!canStart)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showAddCandidate) {
            AddCandidateSheet()
        }
        .onChange(of: selectedCandidate) { _, _ in
            resetToRoleDefaults()
        }
    }

    // MARK: - Phase Row

    @ViewBuilder
    private func phaseRow(at index: Int, phase: PlannedPhase) -> some View {
        HStack(spacing: 8) {
            Image(systemName: phase.rubric != nil ? "checklist" : "bubble.left.and.bubble.right")
                .foregroundStyle(phase.rubric != nil ? .cyan : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Phase title", text: Binding(
                    get: { phase.title },
                    set: { plannedPhases[index].title = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.body)

                if !activeRubrics.isEmpty {
                    Picker("Rubric", selection: Binding(
                        get: { plannedPhases[index].rubric?.id },
                        set: { newID in
                            plannedPhases[index].rubric = activeRubrics.first { $0.id == newID }
                            // Auto-update title when rubric is freshly assigned
                            // and the user hasn't customized the title yet.
                            if let rubric = plannedPhases[index].rubric,
                               Self.placeholderTitles.contains(plannedPhases[index].title) {
                                plannedPhases[index].title = rubric.name
                            }
                        }
                    )) {
                        Text("(unscored)").tag(nil as UUID?)
                        ForEach(roleScopedRubrics) { rubric in
                            Text(rubric.name).tag(rubric.id as UUID?)
                        }
                        if !roleScopedRubrics.isEmpty
                            && roleScopedRubrics.count != activeRubrics.count {
                            Divider()
                            ForEach(activeRubrics.filter { r in !roleScopedRubrics.contains(where: { $0.id == r.id }) }) { rubric in
                                Text(rubric.name).tag(rubric.id as UUID?)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Spacer()

            Button {
                plannedPhases.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Remove this phase")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    /// Build a sensible default phase plan for the selected candidate's role.
    /// Pattern: Intro → all role-scoped rubrics in their natural order →
    /// Conclusion. If no role is selected or no rubrics match, falls back
    /// to a bare Intro/Conclusion shell that the user fills in manually.
    private func resetToRoleDefaults() {
        var phases: [PlannedPhase] = [.intro()]
        for rubric in roleScopedRubrics {
            phases.append(.from(rubric: rubric))
        }
        phases.append(.conclusion())
        plannedPhases = phases
    }

    private func startInterview() {
        guard let candidate = selectedCandidate else { return }
        let interviewerContacts = activeInterviewers.filter { selectedInterviewers.contains($0.id) }
        interviewViewModel.startInterview(
            candidate: candidate,
            plannedPhases: plannedPhases,
            interviewers: interviewerContacts,
            notes: preNotes.isEmpty ? nil : preNotes,
            in: modelContext
        )
    }
}
