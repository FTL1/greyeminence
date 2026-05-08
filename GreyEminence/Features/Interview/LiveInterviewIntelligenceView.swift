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
    @Query(sort: \Rubric.createdAt, order: .reverse) private var allRubrics: [Rubric]

    private var recordingVM: RecordingViewModel {
        interviewViewModel.recordingViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Phase icons (left) + transition controls + Impressions (right)
            HStack(spacing: 0) {
                phaseIcons
                phaseControls
                    .padding(.leading, 6)
                Spacer(minLength: 8)
                impressionsStrip
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.bar.opacity(0.3))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if interviewViewModel.isRubricPhase,
                       let phase = interviewViewModel.interview?.activePhase {
                        PhaseRubricBoard(phase: phase, viewModel: interviewViewModel)
                    } else {
                        phaseOverview
                    }
                    PhaseSignalsStrip(viewModel: interviewViewModel)
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

                if !phase.assignedInterviewers.isEmpty {
                    ownerInitials(phase.assignedInterviewers)
                }
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

    /// Right-of-icon-strip transition controls. "Next" closes the active
    /// phase and advances; the ellipsis menu adds an ad-hoc phase or
    /// ends the active phase without advancing. Replaces the chip-row
    /// controls that used to live in InterviewLiveHeader.
    private var phaseControls: some View {
        HStack(spacing: 4) {
            Button {
                interviewViewModel.advancePhase(in: modelContext)
            } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Advance to the next planned phase")

            Menu {
                Button("End Active Phase") {
                    interviewViewModel.endActivePhase(in: modelContext)
                }
                Divider()
                Section("Add ad-hoc phase") {
                    ForEach(allRubrics.filter { !$0.isArchived }) { rubric in
                        Button(rubric.name) {
                            interviewViewModel.addAdHocPhase(
                                title: rubric.name,
                                rubric: rubric,
                                in: modelContext
                            )
                        }
                    }
                    Divider()
                    Button("Unscored Discussion") {
                        interviewViewModel.addAdHocPhase(
                            title: "Discussion",
                            rubric: nil,
                            in: modelContext
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More phase actions")
        }
        .padding(.bottom, 14)
    }

    /// Compact horizontal stack of assigned interviewer initials, used
    /// under each phase icon to remind whoever's running the phase that
    /// they own it. Caps at 3 visible bubbles; spills into a "+N" tail
    /// so the strip doesn't get cluttered for big panels.
    @ViewBuilder
    private func ownerInitials(_ contacts: [Contact]) -> some View {
        HStack(spacing: -3) {
            ForEach(contacts.prefix(3)) { contact in
                Text(contact.initials)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 12, height: 12)
                    .background(contact.avatarColor.gradient, in: Circle())
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 0.8))
            }
            if contacts.count > 3 {
                Text("+\(contacts.count - 3)")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .background(Color.secondary.opacity(0.25), in: Circle())
            }
        }
        .help("Phase owners: \(contacts.map(\.name).joined(separator: ", "))")
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

}

// MARK: - Phase Rubric Board (live grading view)

private struct CriterionKey: Hashable {
    let sectionID: UUID
    let signal: String
}

private struct PhaseRubricBoard: View {
    let phase: InterviewPhase
    var viewModel: InterviewRecordingViewModel

    @State private var briefCollapsed = false
    @State private var expandedCriteria: Set<CriterionKey> = []

    private var sortedScores: [InterviewSectionScore] {
        phase.sectionScores.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(spacing: 10) {
            BriefHeader(rubric: phase.rubric, isCollapsed: $briefCollapsed)
            ForEach(sortedScores) { score in
                PhaseSectionCard(
                    score: score,
                    viewModel: viewModel,
                    expandedCriteria: $expandedCriteria
                )
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Brief Header (collapsible candidate brief)

private struct BriefHeader: View {
    let rubric: Rubric?
    @Binding var isCollapsed: Bool

    var body: some View {
        if let rubric, let md = rubric.candidateInstructions,
           !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button { isCollapsed.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(isCollapsed ? "Show candidate brief" : "Hide candidate brief")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if !isCollapsed {
                    CandidateInstructionsPanel(sectionTitle: rubric.name, markdown: md)
                }
            }
        }
    }
}

// MARK: - Phase Section Card

private struct PhaseSectionCard: View {
    @Bindable var score: InterviewSectionScore
    var viewModel: InterviewRecordingViewModel
    @Binding var expandedCriteria: Set<CriterionKey>

    @State private var userExpandedNote: Bool = false

    private var rubricSection: RubricSectionSnapshot? {
        viewModel.rubricSection(withID: score.rubricSectionID)
    }

    private var evaluationsBySignal: [String: CriterionEvaluationSnapshot] {
        viewModel.criterionEvaluationsBySignal(for: score.rubricSectionID)
    }

    private var coveredCount: Int {
        evaluationsBySignal.values.filter {
            $0.status == .scored || $0.status == .partialEvidence
        }.count
    }

    private var totalCount: Int {
        rubricSection?.criteria.count ?? 0
    }

    private var hasExistingNote: Bool {
        !(score.interviewerNotes?.isEmpty ?? true)
    }

    private var noteFieldVisible: Bool {
        userExpandedNote || hasExistingNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            criteriaList

            Divider()
                .padding(.horizontal, 10)
                .padding(.top, 4)

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            if noteFieldVisible {
                noteField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(score.rubricSectionTitle.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.0)
            Spacer(minLength: 8)
            if totalCount > 0 {
                Text("\(coveredCount) / \(totalCount) covered")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            aiGradeChip
        }
    }

    @ViewBuilder
    private var aiGradeChip: some View {
        if let aiGrade = score.aiGrade {
            HStack(spacing: 4) {
                Text("AI")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(aiGrade.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(aiGrade.color)
                if let conf = score.aiConfidence {
                    Text("\(Int(conf * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(aiGrade.color.opacity(0.15), in: Capsule())
        } else {
            Text("AI  --")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var criteriaList: some View {
        if let section = rubricSection, !section.criteria.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(section.criteria, id: \.signal) { criterion in
                    let key = CriterionKey(sectionID: score.rubricSectionID, signal: criterion.signal)
                    CriterionLine(
                        signal: criterion.signal,
                        evaluation: evaluationsBySignal[criterion.signal],
                        isExpanded: expandedCriteria.contains(key),
                        onToggle: { toggle(key) },
                        onJumpToTimestamp: viewModel.scrollTranscriptToTimestamp
                    )
                }
            }
        } else {
            Text("No criteria defined for this section.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Your")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { score.interviewerGrade },
                set: { viewModel.updateInterviewerGrade(sectionID: score.rubricSectionID, grade: $0) }
            )) {
                Text("--").tag(nil as LetterGrade?)
                ForEach(LetterGrade.allCases, id: \.self) { grade in
                    Text(grade.label).tag(grade as LetterGrade?)
                }
            }
            .labelsHidden()
            .frame(width: 64)
            .controlSize(.small)

            agreementChip

            Spacer()

            if !hasExistingNote {
                Button {
                    userExpandedNote.toggle()
                } label: {
                    Label(
                        userExpandedNote ? "hide note" : "add note",
                        systemImage: "square.and.pencil"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Small chip to the right of the picker: green ◇ when interviewer
    /// matches AI, orange △ with the AI grade label when they disagree,
    /// nothing while one side is missing.
    @ViewBuilder
    private var agreementChip: some View {
        if let ai = score.aiGrade, let me = score.interviewerGrade {
            if ai == me {
                Text("◇ AI agrees")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.green.opacity(0.8))
            } else {
                Text("△ AI: \(ai.label)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    private var noteField: some View {
        TextField(
            "Section note…",
            text: Binding(
                get: { score.interviewerNotes ?? "" },
                set: {
                    viewModel.updateInterviewerNotes(
                        sectionID: score.rubricSectionID,
                        notes: $0
                    )
                }
            ),
            axis: .vertical
        )
        .lineLimit(1...4)
        .font(.system(size: 11))
        .textFieldStyle(.plain)
        .padding(6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
    }

    private func toggle(_ key: CriterionKey) {
        if !expandedCriteria.insert(key).inserted {
            expandedCriteria.remove(key)
        }
    }
}

// MARK: - Criterion Line (one row inside a card)

private struct CriterionLine: View {
    let signal: String
    let evaluation: CriterionEvaluationSnapshot?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onJumpToTimestamp: (String) -> Void

    private var status: CriterionStatus {
        evaluation?.status ?? .notYetDiscussed
    }

    private var hasEvidence: Bool {
        !(evaluation?.evidence.isEmpty ?? true) ||
            !(evaluation?.summary?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: status.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(status.color)
                        .frame(width: 12)
                    Text(signal)
                        .font(.system(size: 11))
                        .foregroundStyle(status == .notYetDiscussed ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let conf = evaluation?.confidence, conf > 0 {
                        Text("\(Int(conf * 100))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if hasEvidence {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .disabled(!hasEvidence)

            if isExpanded, hasEvidence {
                EvidenceQuotes(
                    evaluation: evaluation,
                    onJumpToTimestamp: onJumpToTimestamp
                )
                .padding(.leading, 30)
                .padding(.trailing, 10)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Evidence Quotes (shown under an expanded criterion)

private struct EvidenceQuotes: View {
    let evaluation: CriterionEvaluationSnapshot?
    let onJumpToTimestamp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let summary = evaluation?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 1)
            }
            if let evidence = evaluation?.evidence {
                ForEach(Array(evidence.enumerated()), id: \.offset) { _, ev in
                    HStack(alignment: .top, spacing: 4) {
                        if !ev.timestamp.isEmpty {
                            Button {
                                onJumpToTimestamp(ev.timestamp)
                            } label: {
                                Text(ev.timestamp)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            .help("Jump to transcript")
                        }
                        Text("\u{201C}\(ev.quote)\u{201D}")
                            .font(.system(size: 10))
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

// MARK: - Phase Signals Strip (strengths / weaknesses / red flags / overall)

private struct PhaseSignalsStrip: View {
    var viewModel: InterviewRecordingViewModel

    var body: some View {
        let s = viewModel.strengths
        let w = viewModel.weaknesses
        let r = viewModel.redFlags
        let o = viewModel.overallAssessment
        if s.isEmpty && w.isEmpty && r.isEmpty && o.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(.secondary.opacity(0.25))
                        .frame(height: 1)
                    Text("PHASE SIGNALS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                    Rectangle()
                        .fill(.secondary.opacity(0.25))
                        .frame(height: 1)
                }
                ForEach(s, id: \.self) { line(icon: "arrow.up.circle.fill", color: .green, text: $0) }
                ForEach(w, id: \.self) { line(icon: "arrow.down.circle.fill", color: .orange, text: $0) }
                ForEach(r, id: \.self) { line(icon: "flag.fill", color: .red, text: $0) }
                if !o.isEmpty {
                    line(icon: "info.circle", color: .secondary, text: o, lineLimit: 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    private func line(
        icon: String,
        color: Color,
        text: String,
        lineLimit: Int = 2
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 12)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Notes Table (used by right panel)

struct InterviewNotesTable: View {
    var interviewViewModel: InterviewRecordingViewModel

    @State private var draftText: String = ""
    /// When true, the next note attaches as a sub-note of the most recent
    /// top-level note in the active phase. Toggled with Tab in the composer.
    @State private var pendingSubNote: Bool = false
    @State private var expandedHistoryIDs: Set<String> = []
    @FocusState private var composerFocused: Bool

    private struct HistoryGroup: Identifiable {
        let id: String
        let title: String
        let notes: [InterviewNote]
    }

    private var activePhase: InterviewPhase? {
        interviewViewModel.interview?.activePhase
    }

    private var activePhaseTopLevelNotes: [InterviewNote] {
        guard let phaseID = activePhase?.id else { return [] }
        return interviewViewModel.notes
            .filter { $0.parentNote == nil && $0.phase?.id == phaseID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Past phases (started or skipped) plus any unphased bucket, in display
    /// order. Empty when there's nothing worth surfacing in History.
    private var historyGroups: [HistoryGroup] {
        let phases = interviewViewModel.interview?.orderedPhases ?? []
        let activeID = activePhase?.id
        var groups: [HistoryGroup] = phases
            .filter { $0.id != activeID && $0.status != .planned }
            .map { phase in
                HistoryGroup(
                    id: phase.id.uuidString,
                    title: phase.title,
                    notes: notes(for: phase.id)
                )
            }
        let unphased = interviewViewModel.notes
            .filter { $0.parentNote == nil && $0.phase == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        if !unphased.isEmpty {
            groups.append(HistoryGroup(id: "unphased", title: "Unphased", notes: unphased))
        }
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                phaseBanner
                composer
                Divider()
                activeNotesList
                if !historyGroups.isEmpty {
                    historyHeader
                    historyList
                }
            }
            .padding(10)
        }
        .onAppear { composerFocused = true }
    }

    // MARK: Phase banner

    @ViewBuilder
    private var phaseBanner: some View {
        if let phase = activePhase {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(phase.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                Spacer()
                let count = activePhaseTopLevelNotes.count
                Text("\(count) note\(count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("NO ACTIVE PHASE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    // MARK: Composer

    private var composerPlaceholder: String {
        if pendingSubNote { return "Sub-note…" }
        if let phase = activePhase { return "Note for \(phase.title)…" }
        return "Type a note…"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if pendingSubNote {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.cyan)
                        .padding(.top, 7)
                }
                TextField(composerPlaceholder, text: $draftText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(composerFocused ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .onKeyPress(.return, phases: .down) { press in
                        // Option+Return inserts a literal newline; everything
                        // else submits with a sentiment derived from modifiers.
                        if press.modifiers.contains(.option) {
                            return .ignored
                        }
                        if press.modifiers.contains(.command) {
                            submit(.wow); return .handled
                        }
                        if press.modifiers.contains(.shift) {
                            submit(.redFlag); return .handled
                        }
                        submit(.neutral)
                        return .handled
                    }
                    .onKeyPress(.tab, phases: .down) { _ in
                        pendingSubNote.toggle()
                        return .handled
                    }
            }

            HStack(spacing: 6) {
                hintChip("↩ add", color: .secondary)
                hintChip("⌘↩ wow", color: .green)
                hintChip("⇧↩ flag", color: .red)
                hintChip(pendingSubNote ? "⇥ top-level" : "⇥ sub-note", color: .cyan)
                Spacer()
            }
        }
    }

    private func hintChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.10))
            )
    }

    private func submit(_ sentiment: NoteSentiment) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pendingSubNote, let lastTop = activePhaseTopLevelNotes.last {
            interviewViewModel.addNote(text: trimmed, sentiment: sentiment, parent: lastTop)
        } else {
            interviewViewModel.addNote(text: trimmed, sentiment: sentiment)
        }
        draftText = ""
        pendingSubNote = false
        composerFocused = true
    }

    // MARK: Active phase notes

    @ViewBuilder
    private var activeNotesList: some View {
        if activePhaseTopLevelNotes.isEmpty {
            Text("No notes for this phase yet.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(activePhaseTopLevelNotes) { note in
                    NoteRow(note: note, viewModel: interviewViewModel, depth: 0)
                }
            }
        }
    }

    // MARK: History

    private var historyHeader: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(height: 1)
            Text("HISTORY")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(historyGroups) { group in
                CollapsedNotesSection(
                    title: group.title,
                    notes: group.notes,
                    isExpanded: expandedHistoryIDs.contains(group.id),
                    viewModel: interviewViewModel,
                    onToggle: { toggleExpansion(group.id) }
                )
            }
        }
    }

    private func notes(for phaseID: UUID) -> [InterviewNote] {
        interviewViewModel.notes
            .filter { $0.parentNote == nil && $0.phase?.id == phaseID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func toggleExpansion(_ id: String) {
        if !expandedHistoryIDs.insert(id).inserted {
            expandedHistoryIDs.remove(id)
        }
    }
}

// MARK: - Collapsed Phase Section

private struct CollapsedNotesSection: View {
    let title: String
    let notes: [InterviewNote]
    let isExpanded: Bool
    var viewModel: InterviewRecordingViewModel
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if notes.isEmpty {
                    Text("No notes")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 18)
                        .padding(.vertical, 2)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(notes) { note in
                            NoteRow(note: note, viewModel: viewModel, depth: 0)
                        }
                    }
                    .padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: - Note Row

private struct NoteRow: View {
    @Bindable var note: InterviewNote
    var viewModel: InterviewRecordingViewModel
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                connectorGlyph

                TextField("", text: $note.text, axis: .vertical)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)

                Button {
                    note.sentiment = note.sentiment.next()
                } label: {
                    sentimentGlyph(note.sentiment)
                        .font(.system(size: 10))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tap to cycle: neutral → wow → red flag")
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(rowBackground(note.sentiment))
            .contextMenu {
                Button("Mark Wow") { note.sentiment = .wow }
                Button("Flag Red") { note.sentiment = .redFlag }
                Button("Clear Flag") { note.sentiment = .neutral }
                Divider()
                if note.parentNote == nil {
                    Button("Make Sub-note") { viewModel.indentNote(note) }
                } else {
                    Button("Promote to Top-level") { viewModel.dedentNote(note) }
                }
                Divider()
                Button("Delete", role: .destructive) { viewModel.deleteNote(note) }
            }

            ForEach(note.subNotes.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                NoteRow(note: sub, viewModel: viewModel, depth: depth + 1)
            }
        }
    }

    /// Leading glyph: `─` for top-level, `└` (with indentation) for sub-notes.
    @ViewBuilder
    private var connectorGlyph: some View {
        if depth > 0 {
            HStack(spacing: 0) {
                if depth > 1 {
                    Spacer().frame(width: CGFloat(depth - 1) * 12)
                }
                Text("└")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10, alignment: .leading)
            }
            .padding(.top, 1)
        } else {
            Text("─")
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 10, alignment: .leading)
                .padding(.top, 1)
        }
    }

    @ViewBuilder
    private func sentimentGlyph(_ sentiment: NoteSentiment) -> some View {
        switch sentiment {
        case .neutral:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tertiary)
        case .wow:
            Image(systemName: "star.fill")
                .foregroundStyle(.green)
        case .redFlag:
            Image(systemName: "flag.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func rowBackground(_ sentiment: NoteSentiment) -> some View {
        switch sentiment {
        case .neutral:
            Color.clear
        case .wow:
            RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.07))
        case .redFlag:
            RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.08))
        }
    }
}
