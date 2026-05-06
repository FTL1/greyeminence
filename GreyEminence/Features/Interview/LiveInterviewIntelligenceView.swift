import SwiftUI
import SwiftData

// MARK: - Bell-Curve Gradient Scoring

func bellCurveColor(for normalizedValue: Double) -> Color {
    let v = min(max(normalizedValue, 0), 1)
    let distance = abs(v - 0.80) / 0.80
    let greenAmount = max(1.0 - distance * 2.5, 0)
    if greenAmount > 0.5 {
        return Color(red: (1.0 - greenAmount) * 0.8, green: 0.7, blue: 0.1)
    } else if v < 0.5 {
        return Color(red: 0.8, green: max(v * 1.4, 0.2), blue: 0.1)
    } else {
        return Color(red: 0.8, green: max(greenAmount * 1.2, 0.2), blue: 0.1)
    }
}

// MARK: - Main Panel (no header — header is in InterviewHubView)

struct LiveInterviewIntelligenceView: View {
    @Environment(\.modelContext) private var modelContext
    var interviewViewModel: InterviewRecordingViewModel
    @Query(sort: \InterviewImpressionTrait.sortOrder) private var traits: [InterviewImpressionTrait]

    private var recordingVM: RecordingViewModel {
        interviewViewModel.recordingViewModel
    }

    private var activeScore: InterviewSectionScore? {
        guard let id = interviewViewModel.activeSectionID else { return nil }
        return interviewViewModel.sectionScores.first { $0.rubricSectionID == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Phase icons (left) + Impressions (right)
            HStack(spacing: 0) {
                phaseIcons
                Spacer(minLength: 8)
                impressionsStrip
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.bar.opacity(0.3))

            Divider()

            // Content for active phase
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if interviewViewModel.isRubricPhase, let score = activeScore {
                        ActiveSectionDetail(score: score, interviewViewModel: interviewViewModel)
                            .padding(.horizontal)
                    } else {
                        phaseOverview
                    }

                    // Strengths / Weaknesses / Red Flags
                    if !interviewViewModel.strengths.isEmpty {
                        signalList(title: "Strengths", items: interviewViewModel.strengths, icon: "arrow.up.circle.fill", color: .green)
                    }
                    if !interviewViewModel.weaknesses.isEmpty {
                        signalList(title: "Weaknesses", items: interviewViewModel.weaknesses, icon: "arrow.down.circle.fill", color: .orange)
                    }
                    if !interviewViewModel.redFlags.isEmpty {
                        signalList(title: "Red Flags", items: interviewViewModel.redFlags, icon: "flag.fill", color: .red)
                    }

                    if !interviewViewModel.overallAssessment.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overall Assessment")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(interviewViewModel.overallAssessment)
                                .font(.caption)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    // MARK: - Phase Icon Buttons

    /// One icon per *interview phase* (intro / system design / coding /
    /// conclusion / etc.). Sections inside a phase happen in parallel
    /// against the active rubric and are surfaced as the criteria
    /// checklist in `ActiveSectionDetail`, not as separate path nodes.
    /// Falls back to the legacy intro→sections→conclusion pseudo-strip
    /// only when the interview wasn't planned with phases (shouldn't
    /// happen post-V2 schema but defensive).
    private var phaseIcons: some View {
        let phases = interviewViewModel.interview?.orderedPhases ?? []
        return HStack(spacing: 2) {
            ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                phaseIconButton(phase: phase)
                if index < phases.count - 1 {
                    phaseConnector
                }
            }
        }
    }

    private func phaseIconButton(phase: InterviewPhase) -> some View {
        let isActive = phase.status == .active
        let composite = phaseComposite(phase)
        let summaryGrade: LetterGrade? = composite.map { LetterGrade.from(gradePoints: $0) }

        return Menu {
            Button("Set Active") {
                interviewViewModel.activatePhase(phase, in: modelContext)
            }
            Divider()
            Section("Icon") {
                ForEach(PhaseIconCatalog.symbols, id: \.self) { sym in
                    Button {
                        phase.iconName = sym
                    } label: {
                        Label(sym, systemImage: sym)
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: phase.resolvedIconName)
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? .cyan : .secondary)
                        .frame(width: 28, height: 28)
                        .background(isActive ? Color.cyan.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? .cyan : .clear, lineWidth: 1.5))

                    if let grade = summaryGrade {
                        Text(grade.label)
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 2)
                            .background(bellCurveColor(for: grade.gradePoints / 4.0), in: RoundedRectangle(cornerRadius: 2))
                            .offset(x: 3, y: -3)
                    }
                }

                Text(phase.title)
                    .font(.system(size: 8, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? .cyan : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(phase.title)
    }

    private var phaseConnector: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 8, height: 1.5)
            .padding(.bottom, 14)
    }

    /// Weighted composite gradePoints across this phase's section
    /// scores. Nil when no scores have grades yet.
    private func phaseComposite(_ phase: InterviewPhase) -> Double? {
        let weighted: [(Double, Double)] = phase.sectionScores.compactMap { s in
            guard let gp = s.effectiveGradePoints else { return nil }
            return (gp, s.weight)
        }
        let totalWeight = weighted.reduce(0.0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        return weighted.reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    // MARK: - Impressions Strip

    /// Fixed colors per position: 1=red, 2=yellow, 3=blue, 4=green, 5=brown
    private static let dotColors: [Color] = [
        .red,
        .yellow,
        Color(red: 0.2, green: 0.4, blue: 0.8),  // blue
        .green,
        Color(red: 0.45, green: 0.28, blue: 0.08), // deep brown
    ]

    // Impression icons + dot mapping
    private static let impressionIcons: [String: String] = [
        "Nervousness": "heart.text.clipboard",
        "Clarity": "text.bubble",
        "Fun to Work With": "face.smiling",
        "Charisma": "sparkles",
        "Curiosity": "questionmark.circle",
    ]

    private var impressionsStrip: some View {
        HStack(spacing: 4) {
            ForEach(traits) { trait in
                if let impression = interviewViewModel.impressions.first(where: { $0.traitName == trait.name }) {
                    let humanColor = Self.dotColors[min(impression.value - 1, 4)]
                    let icon = Self.impressionIcons[trait.name] ?? "circle"

                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            // Icon
                            Image(systemName: icon)
                                .font(.system(size: 12))
                                .foregroundStyle(humanColor)
                                .frame(width: 28, height: 28)
                                .background(humanColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                .help(trait.name)

                            VStack(alignment: .leading, spacing: 1) {
                                // AI dot row (read-only) — only when the AI
                                // has produced a value.
                                if let aiValue = impression.aiValue {
                                    let aiColor = Self.dotColors[min(aiValue - 1, 4)]
                                    HStack(spacing: 3) {
                                        Text("AI")
                                            .font(.system(size: 6, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 10, alignment: .leading)
                                        ForEach(1...5, id: \.self) { val in
                                            Circle()
                                                .stroke(val <= aiValue ? aiColor : Color.secondary.opacity(0.25), lineWidth: 1.5)
                                                .frame(width: 7, height: 7)
                                                .help(trait.label(for: val))
                                        }
                                    }
                                }

                                // Interviewer dot row (tappable)
                                HStack(spacing: 3) {
                                    Text("You")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 10, alignment: .leading)
                                    ForEach(1...5, id: \.self) { val in
                                        Circle()
                                            .fill(val <= impression.value ? humanColor : Color.secondary.opacity(0.15))
                                            .frame(width: 10, height: 10)
                                            .contentShape(Rectangle().size(width: 16, height: 16))
                                            .onTapGesture {
                                                interviewViewModel.updateImpression(traitName: trait.name, value: val)
                                            }
                                            .help(trait.label(for: val))
                                    }
                                }
                            }
                        }

                        // Value label underneath (interviewer's read)
                        Text(trait.label(for: impression.value))
                            .font(.system(size: 7))
                            .foregroundStyle(humanColor)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Phase Overview (Intro / Conclusion)

    private var phaseOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if interviewViewModel.isConclusionPhase {
                Label("Candidate Questions", systemImage: "questionmark.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal)
            } else {
                Label("Introduction & General", systemImage: "person.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal)
            }

            if !recordingVM.streamingSummary.isEmpty {
                AISummarySection(summary: recordingVM.streamingSummary)
            }

            if !recordingVM.followUpQuestions.isEmpty {
                FollowUpQuestionsSection(questions: recordingVM.followUpQuestions)
            }

            if !recordingVM.topics.isEmpty {
                KnowledgeLinksSection(topics: recordingVM.topics)
            }

            if recordingVM.streamingSummary.isEmpty {
                HStack {
                    Spacer()
                    if case .waiting(let secs) = recordingVM.aiActivityState {
                        Text("Summary in \(secs)s...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if case .analyzing = recordingVM.aiActivityState {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Analyzing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Summary will appear once analysis begins")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: - Helpers

    private func signalList(title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Text("  \(item)")
                    .font(.caption)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Active Section Detail

private struct ActiveSectionDetail: View {
    @Bindable var score: InterviewSectionScore
    var interviewViewModel: InterviewRecordingViewModel

    /// Active phase's rubric — the brief lives here (rubric-level), not
    /// per-section.
    private var activeRubric: Rubric? {
        interviewViewModel.interview?.activePhase?.rubric
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(score.rubricSectionTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let effective = score.effectiveLetterGrade {
                    Text(effective.label)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(bellCurveColor(for: effective.gradePoints / 4.0))
                }
            }

            // Phase-level candidate brief — same markdown for every
            // section in the phase. Hidden when the rubric has no brief.
            if let rubric = activeRubric,
               let instructions = rubric.candidateInstructions,
               !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CandidateInstructionsPanel(
                    sectionTitle: rubric.name,
                    markdown: instructions
                )
            }

            HStack(spacing: 16) {
                if let aiGrade = score.aiGrade {
                    HStack(spacing: 4) {
                        Text("AI:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(aiGrade.label)
                            .font(.caption.weight(.bold))
                        if let c = score.aiConfidence {
                            Text("\(Int(c * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text("Your Grade:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { score.interviewerGrade },
                        set: { interviewViewModel.updateInterviewerGrade(sectionID: score.rubricSectionID, grade: $0) }
                    )) {
                        Text("--").tag(nil as LetterGrade?)
                        ForEach(LetterGrade.allCases, id: \.self) { grade in
                            Text(grade.label).tag(grade as LetterGrade?)
                        }
                    }
                    .frame(width: 70)
                    .controlSize(.small)
                }
            }

            // Criteria checklist
            if let rubricSection = interviewViewModel.rubricSnapshot?.sections.first(where: { $0.id == score.rubricSectionID }) {
                let evaluations = interviewViewModel.criterionEvaluations[score.rubricSectionID] ?? []
                let evalDict = Dictionary(evaluations.map { ($0.signal, $0) }, uniquingKeysWith: { _, last in last })

                VStack(alignment: .leading, spacing: 6) {
                    Text("Criteria")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(rubricSection.criteria, id: \.signal) { criterion in
                        CriterionRow(
                            signal: criterion.signal,
                            evaluation: evalDict[criterion.signal],
                            onTapTimestamp: { timestamp in
                                interviewViewModel.scrollTranscriptToTimestamp(timestamp)
                            }
                        )
                    }
                }
            }

            if let rationale = score.aiRationale, !rationale.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rationale")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Add your observations...", text: Binding(
                    get: { score.interviewerNotes ?? "" },
                    set: { interviewViewModel.updateInterviewerNotes(sectionID: score.rubricSectionID, notes: $0) }
                ), axis: .vertical)
                .lineLimit(3...8)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

}

// MARK: - Criterion Row

private struct CriterionRow: View {
    let signal: String
    let evaluation: CriterionEvaluationSnapshot?
    let onTapTimestamp: (String) -> Void

    private var status: CriterionStatus {
        evaluation?.status ?? .notYetDiscussed
    }

    private var statusIcon: String {
        switch status {
        case .scored: "checkmark.circle.fill"
        case .partialEvidence: "circle.dotted"
        case .notYetDiscussed: "circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .scored: .green
        case .partialEvidence: .yellow
        case .notYetDiscussed: .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(signal)
                            .font(.caption)
                            .foregroundStyle(status == .notYetDiscussed ? .tertiary : .primary)

                        if let eval = evaluation, eval.confidence > 0 {
                            Text("\(Int(eval.confidence * 100))%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let summary = evaluation?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if let evidence = evaluation?.evidence, !evidence.isEmpty {
                        ForEach(Array(evidence.enumerated()), id: \.offset) { _, ev in
                            HStack(alignment: .top, spacing: 4) {
                                if !ev.timestamp.isEmpty {
                                    Button {
                                        onTapTimestamp(ev.timestamp)
                                    } label: {
                                        Text(ev.timestamp)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.cyan)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Jump to transcript")
                                }
                                Text("\"\(ev.quote)\"")
                                    .font(.system(size: 10))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.leading, 2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Notes Table (used by right panel)

struct InterviewNotesTable: View {
    var interviewViewModel: InterviewRecordingViewModel
    @State private var newNoteText = ""
    @State private var indentNewNote = false
    @FocusState private var isNewNoteFocused: Bool

    private var topLevelNotes: [InterviewNote] {
        interviewViewModel.notes
            .filter { $0.parentNote == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Notes grouped by phase, in `plannedOrder`. Unphased notes (legacy
    /// or captured outside any active phase) bucket into a final
    /// "Unphased" group.
    private struct NoteGroup: Identifiable {
        let id: String
        let title: String
        let phaseID: UUID?
        let isActive: Bool
        let notes: [InterviewNote]
    }

    private var noteGroups: [NoteGroup] {
        let phases = interviewViewModel.interview?.orderedPhases ?? []
        let activeID = interviewViewModel.interview?.activePhase?.id
        let byPhaseID = Dictionary(grouping: topLevelNotes, by: { $0.phase?.id })
        var groups: [NoteGroup] = phases.map { phase in
            NoteGroup(
                id: phase.id.uuidString,
                title: phase.title,
                phaseID: phase.id,
                isActive: phase.id == activeID,
                notes: (byPhaseID[phase.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            )
        }
        if let unphased = byPhaseID[nil], !unphased.isEmpty {
            groups.append(NoteGroup(
                id: "unphased",
                title: "Unphased",
                phaseID: nil,
                isActive: false,
                notes: unphased.sorted { $0.sortOrder < $1.sortOrder }
            ))
        }
        return groups
    }

    /// Active phase title for the inline composer placeholder.
    private var activePhaseTitle: String? {
        interviewViewModel.interview?.activePhase?.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(noteGroups) { group in
                phaseGroupView(group)
            }

            // Composer — always pins to the active phase via addNote().
            HStack(spacing: 4) {
                Button { indentNewNote.toggle() } label: {
                    Image(systemName: indentNewNote ? "arrow.left.to.line" : "arrow.right.to.line")
                        .font(.system(size: 9))
                        .foregroundStyle(indentNewNote ? Color.cyan : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(indentNewNote ? "Switch to top-level note" : "Switch to sub-note")

                if indentNewNote {
                    Spacer().frame(width: 12)
                }

                Image(systemName: "plus")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                TextField(composerPlaceholder, text: $newNoteText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .focused($isNewNoteFocused)
                    .onSubmit {
                        let text = newNoteText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        // Indent attaches to the most recent note in the
                        // active phase (or any phase, falling back).
                        let activeGroupNotes = noteGroups.first(where: { $0.isActive })?.notes ?? topLevelNotes
                        if indentNewNote, let lastTop = activeGroupNotes.last {
                            interviewViewModel.addNote(text: text, parent: lastTop)
                        } else {
                            interviewViewModel.addNote(text: text)
                        }
                        newNoteText = ""
                        isNewNoteFocused = true
                    }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var composerPlaceholder: String {
        if indentNewNote { return "Sub-note..." }
        if let title = activePhaseTitle {
            return "Note for \(title)..."
        }
        return "Add a note..."
    }

    @ViewBuilder
    private func phaseGroupView(_ group: NoteGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if group.isActive {
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                }
                Text(group.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(group.isActive ? .red : .secondary)
                Text("\(group.notes.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            if group.notes.isEmpty {
                Text("No notes yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                ForEach(group.notes) { note in
                    NoteRow(note: note, interviewViewModel: interviewViewModel, depth: 0)
                }
            }

            Divider()
                .padding(.vertical, 2)
        }
    }
}

private struct NoteRow: View {
    @Bindable var note: InterviewNote
    var interviewViewModel: InterviewRecordingViewModel
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                if depth > 0 { Spacer().frame(width: CGFloat(depth) * 16) }

                // Sentiment mini-menu
                Menu {
                    Button { note.sentiment = .neutral } label: {
                        Label("Neutral", systemImage: "minus.circle")
                    }
                    Button { note.sentiment = .wow } label: {
                        Label("Wow", systemImage: "star.fill")
                    }
                    Button { note.sentiment = .redFlag } label: {
                        Label("Red Flag", systemImage: "flag.fill")
                    }
                } label: {
                    sentimentIcon(note.sentiment)
                        .font(.system(size: 10))
                        .frame(width: 14, height: 14)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help("Flag: \(note.sentiment.rawValue)")

                // Note text — highlighted bg for wow/red flag
                TextField("", text: $note.text)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 2)
                    .background(sentimentBackground(note.sentiment))

                Spacer()

                if note.parentNote != nil {
                    // Sub-note → promote to top level
                    Button { interviewViewModel.dedentNote(note) } label: {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Make top-level note")
                } else {
                    // Top-level → make sub-note of previous sibling
                    Button { interviewViewModel.indentNote(note) } label: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Make sub-note")
                }

                Button { interviewViewModel.deleteNote(note) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)

            ForEach(note.subNotes.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                NoteRow(note: sub, interviewViewModel: interviewViewModel, depth: depth + 1)
            }
        }
    }


    @ViewBuilder
    private func sentimentIcon(_ sentiment: NoteSentiment) -> some View {
        switch sentiment {
        case .neutral:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary.opacity(0.4))
        case .wow:
            Image(systemName: "star.fill")
                .foregroundStyle(.green)
        case .redFlag:
            Image(systemName: "flag.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func sentimentBackground(_ sentiment: NoteSentiment) -> some View {
        switch sentiment {
        case .neutral:
            Color.clear
        case .wow:
            RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.08))
        case .redFlag:
            RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.08))
        }
    }
}
