import SwiftUI
import SwiftData

struct InterviewScorecardView: View {
    @Bindable var interview: Interview
    var interviewViewModel: InterviewRecordingViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewImpressionTrait.sortOrder) private var traits: [InterviewImpressionTrait]
    @State private var isReanalyzing = false
    @State private var reanalysisError: String?
    @State private var sectionScoringStatus: [UUID: SectionScoringState] = [:]
    @State private var scorecardTab: ScorecardTab = .scorecard

    enum ScorecardTab: String, CaseIterable {
        case scorecard = "Scorecard"
        case transcript = "Transcript"
    }

    enum SectionScoringState {
        case pending
        case scoring
        case done
        case failed(String)
    }

    /// Start / In-Progress button to the left of "Score All Sections".
    /// Hidden once the interview is completed or archived — by that point
    /// recording is moot and the scorecard is in review mode.
    @ViewBuilder
    private var startInterviewButton: some View {
        switch interview.status {
        case .scheduled:
            Button {
                interviewViewModel.beginRecording(interview, in: modelContext)
            } label: {
                Label("Start Interview", systemImage: "record.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        case .recording:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .modifier(PulsingModifier())
                Text("In Progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.1), in: Capsule())
        case .completed, .archived:
            EmptyView()
        }
    }

    private var sortedScores: [InterviewSectionScore] {
        // Filter out any potentially deallocated scores (can happen during parallel scoring)
        interview.sectionScores
            .filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Phase groups for the scorecard. One entry per phase that has at
    /// least one section score, ordered by `plannedOrder`. Skips intro /
    /// conclusion phases (rubric == nil, so no scores).
    private struct PhaseGroup: Identifiable {
        let phaseID: UUID
        let title: String
        let plannedOrder: Int
        let scores: [InterviewSectionScore]
        let composite: Double?
        var id: UUID { phaseID }
    }

    private var phaseGroups: [PhaseGroup] {
        var scoresByPhase: [UUID: [InterviewSectionScore]] = [:]
        for score in sortedScores {
            guard let phaseID = score.phase?.id else { continue }
            scoresByPhase[phaseID, default: []].append(score)
        }
        return interview.orderedPhases.compactMap { phase -> PhaseGroup? in
            let raw = scoresByPhase[phase.id] ?? []
            let scores: [InterviewSectionScore] = raw.sorted { (a, b) in
                a.sortOrder < b.sortOrder
            }
            guard !scores.isEmpty else { return nil }
            let weighted: [(Double, Double)] = scores.compactMap { s in
                guard let gp = s.effectiveGradePoints else { return nil }
                return (gp, s.weight)
            }
            let totalWeight = weighted.reduce(0.0) { $0 + $1.1 }
            let composite: Double? = (totalWeight > 0)
                ? weighted.reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
                : nil
            return PhaseGroup(
                phaseID: phase.id,
                title: phase.title,
                plannedOrder: phase.plannedOrder,
                scores: scores,
                composite: composite
            )
        }
    }

    /// Section scores not linked to any phase (legacy / pre-multi-phase
    /// records). Surfaced under a fallback "Ungrouped" header so they
    /// don't silently vanish.
    private var orphanScores: [InterviewSectionScore] {
        sortedScores.filter { $0.phase == nil }
    }

    @ViewBuilder
    private func phaseGroupView(_ group: PhaseGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let composite = group.composite {
                    let grade = LetterGrade.from(gradePoints: composite)
                    Text(grade.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(grade.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(grade.color)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(group.scores) { score in
                scoreCardWithStatus(score)
            }
        }
        .padding(10)
        .background(.bar.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func scoreCardWithStatus(_ score: InterviewSectionScore) -> some View {
        HStack(spacing: 6) {
            InterviewSectionScoreCard(score: score)
            if let status = sectionScoringStatus[score.rubricSectionID] {
                switch status {
                case .pending:
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                case .scoring:
                    ProgressView()
                        .controlSize(.mini)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Picker("", selection: $scorecardTab) {
                    ForEach(ScorecardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                if let templateName = interview.templateNameAtSchedule, !templateName.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(templateName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .help("Scheduled from template: \(templateName)")
                    .padding(.leading, 8)
                }

                Spacer()

                startInterviewButton

                // Score-all only makes sense when the user is looking at
                // the scorecard. Hide it on the Transcript tab so that
                // tab's header has only the picker + (when relevant) the
                // Start Interview button.
                if scorecardTab == .scorecard {
                    if isReanalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await reanalyze() }
                        } label: {
                            Label("Score All Sections", systemImage: "brain")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch scorecardTab {
            case .scorecard:
                scorecardContent
            case .transcript:
                transcriptContent
            }
        }
    }

    private var scorecardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                if let error = reanalysisError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") { reanalysisError = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)
                }

                // Overall score
                overallScoreSection
                    .padding(.horizontal)

                // Recommendation picker
                recommendationSection
                    .padding(.horizontal)

                // Impression sliders (read-only display with values)
                impressionSection
                    .padding(.horizontal)

                // Section scorecards — grouped by phase. Each scored phase
                // (intro/conclusion are skipped; they have no rubric and
                // no sections) gets a header with its composite grade,
                // then its sections.
                ForEach(phaseGroups, id: \.phaseID) { group in
                    phaseGroupView(group)
                        .padding(.horizontal)
                }

                // Orphans: any scores not linked to a phase (legacy data
                // from before the multi-phase migration). Render flat
                // under a fallback header so they're still visible.
                let orphans = orphanScores
                if !orphans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ungrouped")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(orphans) { score in
                            scoreCardWithStatus(score)
                        }
                    }
                    .padding(.horizontal)
                }

                // Strengths / Weaknesses / Red Flags
                if !interview.strengths.isEmpty {
                    signalSection("Strengths", items: interview.strengths, icon: "hand.thumbsup.fill", color: .green)
                }
                if !interview.weaknesses.isEmpty {
                    signalSection("Weaknesses", items: interview.weaknesses, icon: "hand.thumbsdown.fill", color: .orange)
                }
                if !interview.redFlags.isEmpty {
                    signalSection("Red Flags", items: interview.redFlags, icon: "flag.fill", color: .red)
                }

                // Overall Assessment
                if let assessment = interview.overallAssessment, !assessment.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overall Assessment")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(assessment)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }

                // Interviewer notes
                Section {
                    TextEditor(text: Binding(
                        get: { interview.interviewerNotes ?? "" },
                        set: { interview.interviewerNotes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 60)
                    .font(.caption)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )
                } header: {
                    Text("Interviewer Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private var transcriptSegments: [TranscriptSegment] {
        (interview.meeting?.segments ?? []).sorted { $0.startTime < $1.startTime }
    }

    /// Segment IDs where a section marker should be shown (first segment of each new tag).
    private var markerSegmentIDs: [UUID: String] {
        var result: [UUID: String] = [:]
        var lastTag: String?
        for segment in transcriptSegments {
            if let tag = segment.sectionTag, tag != lastTag {
                result[segment.id] = tag
            }
            lastTag = segment.sectionTag
        }
        return result
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if transcriptSegments.isEmpty {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "text.bubble",
                description: Text("This interview has no transcript segments")
            )
        } else {
            let markers = markerSegmentIDs
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(transcriptSegments) { segment in
                        if let markerTitle = markers[segment.id] {
                            SectionMarkerView(
                                title: markerTitle,
                                timestamp: segment.formattedTimestamp
                            )
                        }
                        TranscriptSegmentRow(segment: segment)
                            .contextMenu {
                                Menu("Tag Section") {
                                    Button("Intro") { tagSegment(segment, tag: "Intro", id: InterviewRecordingViewModel.introID) }
                                    ForEach(sortedScores) { score in
                                        Button(score.rubricSectionTitle) {
                                            tagSegment(segment, tag: score.rubricSectionTitle, id: score.rubricSectionID)
                                        }
                                    }
                                    Button("Conclusion") { tagSegment(segment, tag: "Conclusion", id: InterviewRecordingViewModel.conclusionID) }
                                    Divider()
                                    Button("Clear Tag") { tagSegment(segment, tag: nil, id: nil) }
                                }
                            }
                    }
                }
                .padding()
            }
        }
    }

    /// Tag from this segment forward until the next segment that already has a different tag.
    private func tagSegment(_ segment: TranscriptSegment, tag: String?, id: UUID?) {
        guard let startIndex = transcriptSegments.firstIndex(where: { $0.id == segment.id }) else { return }

        for i in startIndex..<transcriptSegments.count {
            let seg = transcriptSegments[i]
            // Stop at the next segment that already has a different tag (unless it's the one we're starting from)
            if i > startIndex, let existingTag = seg.sectionTag, existingTag != segment.sectionTag {
                break
            }
            seg.sectionTag = tag
            seg.sectionTagID = id
        }
        PersistenceGate.save(
            modelContext,
            site: "InterviewScorecardView.tagSegment",
            meetingID: interview.meeting?.id
        )
    }

    // MARK: - Overall Score

    private var overallScoreSection: some View {
        HStack(spacing: 16) {
            if let gp = interview.compositeGradePoints {
                let grade = LetterGrade.from(gradePoints: gp)
                VStack(spacing: 2) {
                    Text(grade.label)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(grade.color)
                    Text(grade.percentRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    Text("—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("No scores yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Score breakdown — phase composites first, sections nested.
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(phaseGroups, id: \.phaseID) { group in
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(.caption2.weight(.semibold))
                        if let composite = group.composite {
                            let grade = LetterGrade.from(gradePoints: composite)
                            Text(grade.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(grade.color)
                        } else {
                            Text("—")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recommendation

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommendation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(OverallRecommendation.allCases, id: \.self) { rec in
                    Button {
                        interview.overallRecommendation = rec
                    } label: {
                        Text(rec.shortLabel)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                interview.overallRecommendation == rec
                                    ? AnyShapeStyle(rec.color.opacity(0.3))
                                    : AnyShapeStyle(Color.secondary.opacity(0.15)),
                                in: Capsule()
                            )
                            .foregroundStyle(interview.overallRecommendation == rec ? rec.color : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(rec.label)
                }
            }
        }
    }

    // MARK: - Impressions

    private var impressionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Impressions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Label("You", systemImage: "person.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Label("AI", systemImage: "sparkle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(interview.impressions.sorted(by: { $0.traitName < $1.traitName })) { impression in
                if let trait = traits.first(where: { $0.name == impression.traitName }) {
                    impressionRow(trait: trait, impression: impression)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func impressionRow(trait: InterviewImpressionTrait, impression: InterviewImpression) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trait.name)
                .font(.caption.weight(.semibold))

            // Interviewer row
            HStack(spacing: 6) {
                Text("You")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                    .lineLimit(1)
                    .fixedSize()
                ForEach(1...5, id: \.self) { value in
                    Circle()
                        .fill(value <= impression.value ? dotColor(impression.value) : .secondary.opacity(0.2))
                        .frame(width: 10, height: 10)
                }
                Text(trait.label(for: impression.value))
                    .font(.caption2)
                    .foregroundStyle(dotColor(impression.value))
            }

            // AI row — hollow dots, only when AI has scored.
            if let aiValue = impression.aiValue {
                HStack(spacing: 6) {
                    Text("AI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    .lineLimit(1)
                    .fixedSize()
                    ForEach(1...5, id: \.self) { value in
                        Circle()
                            .stroke(value <= aiValue ? dotColor(aiValue) : .secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                    Text(trait.label(for: aiValue))
                        .font(.caption2)
                        .foregroundStyle(dotColor(aiValue))
                }
            }
        }
    }

    private func signalSection(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .padding(.top, 4)
                    Text(item)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func dotColor(_ value: Int) -> Color {
        switch value {
        case 1, 5: .orange
        case 3, 4: .green
        default: .secondary
        }
    }

    // MARK: - Reanalyze (Parallel Per-Section)

    @MainActor
    private func reanalyze() async {
        guard !isReanalyzing else { return }
        isReanalyzing = true
        reanalysisError = nil

        defer {
            isReanalyzing = false
            // Clear scoring status after a delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                sectionScoringStatus = [:]
            }
        }

        guard let meeting = interview.meeting else {
            reanalysisError = "No recording linked to this interview."
            LogManager.send("Scoring aborted: no meeting", category: .ai, level: .error)
            return
        }
        guard let rubric = interview.rubric else {
            reanalysisError = "No rubric linked to this interview."
            LogManager.send("Scoring aborted: no rubric", category: .ai, level: .error)
            return
        }

        let client: any AIClient
        do {
            guard let c = try await AIClientFactory.makeClient() else {
                reanalysisError = "AI not configured. Check Settings."
                LogManager.send("Scoring aborted: AIClientFactory returned nil", category: .ai, level: .error)
                return
            }
            client = c
        } catch {
            reanalysisError = "AI client error: \(error.localizedDescription)"
            LogManager.send("Scoring aborted: \(error.localizedDescription)", category: .ai, level: .error)
            return
        }

        let sortedSegments = meeting.segments.sorted { $0.startTime < $1.startTime }

        guard !sortedSegments.isEmpty else {
            reanalysisError = "No transcript segments to analyze."
            return
        }

        // Build segment snapshots per section (using section tags)
        let allSnapshots: [SegmentSnapshot] = sortedSegments
            .map { SegmentSnapshot(speaker: $0.speaker, text: $0.text, formattedTimestamp: $0.formattedTimestamp, isFinal: $0.isFinal) }

        var segmentsBySection: [UUID: [SegmentSnapshot]] = [:]
        for segment in sortedSegments {
            if let tagID = segment.sectionTagID {
                segmentsBySection[tagID, default: []].append(
                    SegmentSnapshot(speaker: segment.speaker, text: segment.text, formattedTimestamp: segment.formattedTimestamp, isFinal: segment.isFinal)
                )
            }
        }

        let rubricSnapshot = rubric.toSnapshot()

        // Initialize all sections as pending
        for section in rubricSnapshot.sections {
            sectionScoringStatus[section.id] = .pending
        }

        // Score all sections in parallel — send only relevant transcript segments
        let meetingID = meeting.id
        let sections = rubricSnapshot.sections

        LogManager.send("Starting parallel scoring: \(sections.count) sections, \(allSnapshots.count) total segments", category: .ai)
        for section in sections {
            let tagged = segmentsBySection[section.id]?.count ?? 0
            LogManager.send("  \(section.title): \(tagged) tagged segments (fallback: \(tagged == 0 ? "full transcript" : "tagged only"))", category: .ai)
        }

        var tasks: [UUID: Task<InterviewAnalysisResult?, Error>] = [:]
        for section in sections {
            sectionScoringStatus[section.id] = .scoring
            let sectionCopy = section
            let rubricCopy = rubricSnapshot
            // Use tagged segments for this section if available, otherwise full transcript
            let sectionSegments = segmentsBySection[section.id] ?? allSnapshots
            tasks[section.id] = Task.detached {
                let service = InterviewIntelligenceService(
                    client: client,
                    rubricContext: rubricCopy,
                    meetingID: meetingID
                )
                return try await service.scoreSingleSection(
                    section: sectionCopy,
                    segments: sectionSegments
                )
            }
        }

        // Collect results and aggregate strengths/weaknesses
        var allStrengths: [String] = []
        var allWeaknesses: [String] = []
        var allRedFlags: [String] = []
        var assessments: [String] = []

        for (sectionID, task) in tasks {
            do {
                if let result = try await task.value {
                    if let score = result.sectionScores.first(where: { $0.sectionID == sectionID }) {
                        applySectionScore(score, sectionID: sectionID)
                        LogManager.send("Section '\(score.sectionTitle)' scored: \(score.grade ?? "nil")", category: .ai)
                    }
                    allStrengths.append(contentsOf: result.strengths)
                    allWeaknesses.append(contentsOf: result.weaknesses)
                    allRedFlags.append(contentsOf: result.redFlags)
                    if !result.overallAssessment.isEmpty {
                        assessments.append(result.overallAssessment)
                    }
                } else {
                    LogManager.send("Section scoring returned nil for \(sectionID)", category: .ai, level: .warning)
                }
                sectionScoringStatus[sectionID] = .done
            } catch {
                sectionScoringStatus[sectionID] = .failed(error.localizedDescription)
                reanalysisError = error.localizedDescription
                LogManager.send("Section scoring failed: \(error.localizedDescription)", category: .ai, level: .error)
            }
        }

        // Persist aggregated strengths/weaknesses/assessment
        interview.strengths = allStrengths
        interview.weaknesses = allWeaknesses
        interview.redFlags = allRedFlags
        interview.overallAssessment = assessments.joined(separator: " ")

        PersistenceGate.save(
            modelContext,
            site: "InterviewScorecardView.parallelScoring",
            critical: true,
            meetingID: interview.meeting?.id
        )
        LogManager.send("Parallel scoring complete", category: .ai)
    }

    private func applySectionScore(_ aiScore: SectionScoreSnapshot, sectionID: UUID) {
        guard let idx = interview.sectionScores.firstIndex(where: { $0.rubricSectionID == sectionID }) else { return }
        let sectionScore = interview.sectionScores[idx]

        if let gradeStr = aiScore.grade {
            sectionScore.aiGrade = LetterGrade(rawValue: gradeStr)
        }
        sectionScore.aiConfidence = aiScore.confidence
        sectionScore.aiRationale = aiScore.rationale

        // Persist section-level evidence as JSON for backwards compat
        let quoteStrings = aiScore.evidence.map { $0.quote }
        if let data = try? JSONEncoder().encode(quoteStrings),
           let str = String(data: data, encoding: .utf8) {
            sectionScore.aiEvidence = str
        }

        // Persist structured evidence items
        for existing in sectionScore.evidenceItems {
            modelContext.delete(existing)
        }
        for ev in aiScore.evidence {
            let item = ScoreEvidence(
                quote: ev.quote,
                timestamp: ev.timestamp,
                criterionSignal: ev.criterion,
                strength: EvidenceStrength(rawValue: ev.strength) ?? .moderate
            )
            item.sectionScore = sectionScore
            sectionScore.evidenceItems.append(item)
        }

        // Persist criterion evaluations
        for existing in sectionScore.criterionEvaluations {
            modelContext.delete(existing)
        }
        for (i, eval) in aiScore.criterionEvaluations.enumerated() {
            let ce = CriterionEvaluation(
                signal: eval.signal,
                status: eval.status,
                confidence: eval.confidence,
                summary: eval.summary,
                sortOrder: i
            )
            ce.sectionScore = sectionScore
            for ev in eval.evidence {
                let cev = CriterionEvidence(
                    quote: ev.quote,
                    timestamp: ev.timestamp,
                    strength: EvidenceStrength(rawValue: ev.strength) ?? .moderate
                )
                cev.criterionEvaluation = ce
                ce.evidenceItems.append(cev)
            }
            sectionScore.criterionEvaluations.append(ce)
        }
    }
}
