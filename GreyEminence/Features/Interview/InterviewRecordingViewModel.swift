import Foundation
import SwiftUI
import SwiftData

/// Pre-call planning input describing one phase the interviewer intends to
/// run. `rubric` may be nil to represent unscored phases (intro, conclusion,
/// freeform discussion). `title` defaults to the rubric name when nil.
struct PlannedPhase: Identifiable {
    let id: UUID
    var title: String
    var rubric: Rubric?

    init(id: UUID = UUID(), title: String, rubric: Rubric? = nil) {
        self.id = id
        self.title = title
        self.rubric = rubric
    }

    static func intro() -> PlannedPhase { PlannedPhase(title: "Intro", rubric: nil) }
    static func conclusion() -> PlannedPhase { PlannedPhase(title: "Conclusion", rubric: nil) }
    static func from(rubric: Rubric) -> PlannedPhase {
        PlannedPhase(title: rubric.name, rubric: rubric)
    }
}

extension PlannedPhase: Hashable {
    static func == (lhs: PlannedPhase, rhs: PlannedPhase) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Observable
@MainActor
final class InterviewRecordingViewModel {
    let recordingViewModel: RecordingViewModel

    // Interview state
    var interview: Interview?
    var completedInterview: Interview?
    /// Section scores for the currently active phase, mirrored for UI binding.
    /// When the active phase changes, this array is repopulated from the new
    /// phase's `sectionScores`.
    var sectionScores: [InterviewSectionScore] = []
    var impressions: [InterviewImpression] = []
    var bookmarks: [InterviewBookmark] = []
    var notes: [InterviewNote] = []
    var rubricAnalysisState: RecordingViewModel.AIActivityState = .idle

    /// Conclusion uses a well-known UUID distinct from nil (Intro).
    static let introID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let conclusionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// The currently active interview phase.
    /// introID = Intro/General, conclusionID = Conclusion, rubric UUID = that section.
    var activePhaseID: UUID = InterviewRecordingViewModel.introID

    var isIntroPhase: Bool { activePhaseID == Self.introID }
    var isConclusionPhase: Bool { activePhaseID == Self.conclusionID }
    var isRubricPhase: Bool { !isIntroPhase && !isConclusionPhase }

    /// The rubric section ID if a rubric section is active, nil otherwise.
    var activeSectionID: UUID? {
        isRubricPhase ? activePhaseID : nil
    }

    var activeSectionTitle: String {
        if isIntroPhase { return "Intro" }
        if isConclusionPhase { return "Conclusion" }
        if let score = sectionScores.first(where: { $0.rubricSectionID == activePhaseID }) {
            return score.rubricSectionTitle
        }
        return "General Discussion"
    }

    func setActivePhase(_ phaseID: UUID) {
        activePhaseID = phaseID
        // Tag subsequent transcript segments with this section
        recordingViewModel.currentSectionTag = activeSectionTitle
        recordingViewModel.currentSectionTagID = phaseID
    }

    // Criterion evaluations per section
    var criterionEvaluations: [UUID: [CriterionEvaluationSnapshot]] = [:]
    /// Snapshot of the *currently active phase's* rubric. Recomputed each
    /// time the active phase changes. Nil when no phase is active or the
    /// active phase has no rubric (intro / conclusion / freeform).
    var rubricSnapshot: RubricSnapshot?
    var impressionTraitSnapshots: [ImpressionTraitSnapshot] = []

    // Scroll-to-transcript support
    var scrollToSegmentID: UUID?

    // AI results
    var strengths: [String] = []
    var weaknesses: [String] = []
    var redFlags: [String] = []
    var overallAssessment: String = ""

    // Interview intelligence service
    private var rubricAnalysisTask: Task<Void, Never>?

    var isInterviewActive: Bool {
        interview != nil && recordingViewModel.state != .idle
    }

    init(recordingViewModel: RecordingViewModel) {
        self.recordingViewModel = recordingViewModel
    }

    // MARK: - Interview Lifecycle

    /// Single-rubric convenience kept for backward compatibility with callers
    /// that haven't migrated to multi-phase planning yet. Wraps the rubric in
    /// a single planned phase plus an intro and conclusion phase.
    func startInterview(
        candidate: Candidate,
        rubric: Rubric,
        interviewers: [Contact],
        notes: String?,
        in modelContext: ModelContext
    ) {
        startInterview(
            candidate: candidate,
            plannedPhases: [.intro(), .from(rubric: rubric), .conclusion()],
            interviewers: interviewers,
            notes: notes,
            in: modelContext
        )
    }

    /// Multi-phase interview start. `plannedPhases` is the ordered sequence
    /// the interviewer intends to run. The first phase (whatever it is) is
    /// activated immediately; subsequent phases stay `.planned` until the
    /// interviewer transitions through them.
    func startInterview(
        candidate: Candidate,
        plannedPhases: [PlannedPhase],
        interviewers: [Contact],
        notes: String?,
        in modelContext: ModelContext
    ) {
        // Use the first scored phase's rubric as the legacy `Interview.rubric`
        // pointer so older code paths and the backfill keep working. If
        // there's no scored phase, leave it nil.
        let firstScoredRubric = plannedPhases.compactMap(\.rubric).first
        let interview = Interview(candidate: candidate, rubric: firstScoredRubric)
        interview.status = .recording
        interview.interviewerNotes = notes
        interview.interviewers = interviewers
        modelContext.insert(interview)

        // Build phase models from the planning input. Order matters; we
        // assign plannedOrder by position so reordering later doesn't
        // require array index gymnastics.
        for (idx, planned) in plannedPhases.enumerated() {
            let phase = InterviewPhase(
                title: planned.title,
                rubric: planned.rubric,
                plannedOrder: idx,
                status: .planned
            )
            phase.interview = interview
            interview.phases.append(phase)
            populateSectionScores(for: phase, on: interview)
        }

        let traitDescriptor = FetchDescriptor<InterviewImpressionTrait>(
            sortBy: [SortDescriptor(\InterviewImpressionTrait.sortOrder)]
        )
        let traits = (try? modelContext.fetch(traitDescriptor)) ?? []
        var imps: [InterviewImpression] = []
        for trait in traits {
            let impression = InterviewImpression(traitName: trait.name, value: 3) // Start at middle
            impression.interview = interview
            imps.append(impression)
        }

        self.impressionTraitSnapshots = traits.map {
            ImpressionTraitSnapshot(name: $0.name, labels: $0.labels)
        }
        self.interview = interview
        self.impressions = imps
        self.bookmarks = []
        self.strengths = []
        self.weaknesses = []
        self.redFlags = []
        self.overallAssessment = ""

        PersistenceGate.save(
            modelContext,
            site: "InterviewRecordingViewModel.startInterview/initialInsert",
            critical: true
        )

        recordingViewModel.startRecording(in: modelContext)
        if let meeting = recordingViewModel.currentMeeting {
            meeting.isInterviewMeeting = true
            interview.meeting = meeting

            for contact in interviewers {
                if !meeting.attendees.contains(where: { $0.id == contact.id }) {
                    meeting.attendees.append(contact)
                }
            }
            PersistenceGate.save(
                modelContext,
                site: "InterviewRecordingViewModel.startInterview/linkMeeting",
                critical: true,
                meetingID: meeting.id
            )
        }

        // Activate the first planned phase. If the first phase is unscored
        // (intro), the AI loop will silently skip cycles until the
        // interviewer advances to a scored phase.
        if let first = interview.orderedPhases.first {
            activatePhase(first, in: modelContext)
        }

        // Build candidate-context snapshot once (resume extraction is
        // synchronous file I/O — keep it off the per-cycle hot path).
        buildCandidateContextSnapshot()

        // Start rubric analysis loop (offset from standard AI by ~20s).
        // The loop reads the active phase's rubric per cycle, so it
        // tolerates phase changes without restart.
        startRubricAnalysis()
    }

    // MARK: - Phase Transitions

    /// Mark the given phase active and refresh derived state (section
    /// scores mirror, rubric snapshot, segment tag). Closes any other
    /// `.active` phase first to maintain the "at most one active" invariant.
    private func activatePhase(_ phase: InterviewPhase, in modelContext: ModelContext) {
        guard let interview else { return }
        // Close any currently active phase first.
        for other in interview.phases where other.status == .active && other.id != phase.id {
            other.status = .completed
            other.endedAt = .now
        }
        phase.status = .active
        if phase.startedAt == nil {
            phase.startedAt = .now
        }
        // Mirror the active phase's section scores into the VM array so
        // existing UI bindings keep working without per-view rewrites.
        sectionScores = phase.sectionScores.sorted { $0.sortOrder < $1.sortOrder }
        rubricSnapshot = phase.rubric?.toSnapshot()
        // Tag transcript segments with the phase title + ID so live
        // attribution survives across pause/resume — phase boundaries are
        // persisted now, not just held in this VM.
        recordingViewModel.currentSectionTag = phase.title
        recordingViewModel.currentSectionTagID = phase.id
        // Reset section focus to the phase's first section (if any).
        activePhaseID = phase.sectionScores.sorted { $0.sortOrder < $1.sortOrder }.first?.rubricSectionID
            ?? phase.id

        PersistenceGate.save(
            modelContext,
            site: "InterviewRecordingViewModel.activatePhase",
            meetingID: recordingViewModel.currentMeeting?.id
        )
        LogManager.shared.log("Interview phase activated: \(phase.title)", category: .ai)
    }

    /// Advance to the next planned phase in order. Closes the current active
    /// phase and activates the next `.planned` one. No-op if no further
    /// phases remain — the interviewer should call `stopInterview` instead.
    func advancePhase(in modelContext: ModelContext) {
        guard let interview else { return }
        let ordered = interview.orderedPhases
        guard let current = interview.activePhase,
              let currentIdx = ordered.firstIndex(where: { $0.id == current.id }) else {
            if let first = ordered.first(where: { $0.status == .planned }) {
                activatePhase(first, in: modelContext)
            }
            return
        }
        let remaining = ordered.dropFirst(currentIdx + 1)
        if let next = remaining.first(where: { $0.status == .planned }) {
            activatePhase(next, in: modelContext)
        } else {
            closeAndClear(phase: current, in: modelContext, site: "advancePhase/lastClosed")
        }
    }

    /// Mark the active phase `.completed` without auto-advancing — useful when
    /// the next phase needs to be picked manually.
    func endActivePhase(in modelContext: ModelContext) {
        guard let active = interview?.activePhase else { return }
        closeAndClear(phase: active, in: modelContext, site: "endActivePhase")
    }

    private func closeAndClear(
        phase: InterviewPhase,
        in modelContext: ModelContext,
        site: String
    ) {
        phase.status = .completed
        phase.endedAt = .now
        sectionScores = []
        rubricSnapshot = nil
        recordingViewModel.currentSectionTag = nil
        recordingViewModel.currentSectionTagID = nil
        PersistenceGate.save(
            modelContext,
            site: "InterviewRecordingViewModel.\(site)",
            meetingID: recordingViewModel.currentMeeting?.id
        )
    }

    /// Mark a planned phase as `.skipped` without ever activating it. The
    /// interviewer typically calls this when realizing mid-call that they
    /// won't have time for a phase they'd planned.
    func skipPhase(_ phase: InterviewPhase, in modelContext: ModelContext) {
        guard phase.status == .planned else { return }
        phase.status = .skipped
        PersistenceGate.save(
            modelContext,
            site: "InterviewRecordingViewModel.skipPhase",
            meetingID: recordingViewModel.currentMeeting?.id
        )
    }

    /// Append a new phase mid-interview and activate it immediately — the
    /// "pull in a code-review rubric on the fly" affordance.
    func addAdHocPhase(title: String, rubric: Rubric?, in modelContext: ModelContext) {
        guard let interview else { return }
        let nextOrder = (interview.phases.map(\.plannedOrder).max() ?? -1) + 1
        let phase = InterviewPhase(
            title: title,
            rubric: rubric,
            plannedOrder: nextOrder,
            status: .planned
        )
        phase.interview = interview
        interview.phases.append(phase)
        populateSectionScores(for: phase, on: interview)
        activatePhase(phase, in: modelContext)
    }

    /// Pre-create one `InterviewSectionScore` per rubric section on the given
    /// phase so the scoring UI has empty rows to bind to before the AI
    /// produces grades. No-op for unscored phases (rubric == nil).
    private func populateSectionScores(for phase: InterviewPhase, on interview: Interview) {
        guard let rubric = phase.rubric else { return }
        for section in rubric.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let score = InterviewSectionScore(
                rubricSectionID: section.id,
                rubricSectionTitle: section.title,
                sortOrder: section.sortOrder,
                weight: section.weight
            )
            score.interview = interview
            score.phase = phase
            phase.sectionScores.append(score)
            interview.sectionScores.append(score)
        }
    }

    func stopInterview(in modelContext: ModelContext) {
        rubricAnalysisTask?.cancel()
        rubricAnalysisTask = nil

        // Capture reference before reset clears it
        completedInterview = interview

        if let interview {
            interview.status = .completed
            // Close any still-active phase so finalized state is consistent.
            if let active = interview.activePhase {
                active.status = .completed
                active.endedAt = .now
            }
            interview.impressions = impressions
            interview.bookmarks = bookmarks
            interview.notes = notes.filter { $0.parentNote == nil }
        }
        PersistenceGate.save(
            modelContext,
            site: "InterviewRecordingViewModel.stopInterview",
            critical: true,
            meetingID: recordingViewModel.currentMeeting?.id
        )

        // Capture sendable inputs for each scored phase up-front on the
        // main actor. Each tuple has everything the network call needs;
        // SwiftData mutation happens later, back on main, after all the
        // async work returns.
        let allSegments = recordingViewModel.snapshotSegments()
        struct PhaseJob: Sendable {
            let id: UUID
            let snapshot: RubricSnapshot
            let segments: [SegmentSnapshot]
        }
        let jobs: [PhaseJob] = interview?.phases.compactMap { phase in
            guard let rubric = phase.rubric else { return nil }
            let segments = filterSegments(allSegments, between: phase.startedAt, and: phase.endedAt)
            guard !segments.isEmpty else { return nil }
            return PhaseJob(id: phase.id, snapshot: rubric.toSnapshot(), segments: segments)
        } ?? []
        let meetingID = recordingViewModel.currentMeeting?.id
        let traits = impressionTraitSnapshots
        let candidate = candidateContextSnapshot

        recordingViewModel.stopRecording(in: modelContext)

        guard !jobs.isEmpty else {
            rubricAnalysisState = .idle
            return
        }
        rubricAnalysisState = .analyzing
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Network round-trips run in parallel; results applied to
            // SwiftData on main as they arrive. Total wall-clock =
            // max(phase) instead of sum(phase).
            let results: [(UUID, InterviewAnalysisResult)] = await withTaskGroup(
                of: (UUID, InterviewAnalysisResult?).self
            ) { group in
                for job in jobs {
                    group.addTask {
                        guard let client = try? await AIClientFactory.makeClient() else {
                            return (job.id, nil)
                        }
                        let service = InterviewIntelligenceService(
                            client: client,
                            rubricContext: job.snapshot,
                            impressionTraits: traits,
                            candidateContext: candidate,
                            meetingID: meetingID
                        )
                        let result = try? await service.performFinalInterviewAnalysis(segments: job.segments)
                        return (job.id, result)
                    }
                }
                var collected: [(UUID, InterviewAnalysisResult)] = []
                for await (phaseID, maybeResult) in group {
                    if let result = maybeResult {
                        collected.append((phaseID, result))
                    } else {
                        LogManager.shared.log("Final rubric analysis failed for phase \(phaseID)", category: .ai, level: .warning)
                    }
                }
                return collected
            }

            for (phaseID, result) in results {
                self.applyAnalysisResult(result, toPhaseID: phaseID)
            }
            if !results.isEmpty {
                PersistenceGate.save(
                    modelContext,
                    site: "InterviewRecordingViewModel.runFinalRubricAnalysis/parallel",
                    critical: true,
                    meetingID: meetingID
                )
                LogManager.shared.log("Final rubric analysis complete (\(results.count) phase(s))", category: .ai)
            }
            self.rubricAnalysisState = .idle
        }
    }

    /// Filter segments to the time window `[startedAt, endedAt]`. If
    /// `startedAt` is nil the window opens at -inf; if `endedAt` is nil the
    /// window extends to +inf. Segment timestamps are in seconds elapsed
    /// since recording start, but phase boundaries are wall-clock dates —
    /// we convert phases to elapsed seconds via the recording's start.
    private func filterSegments(
        _ segments: [SegmentSnapshot],
        between startedAt: Date?,
        and endedAt: Date?
    ) -> [SegmentSnapshot] {
        guard let recordingStart = recordingViewModel.currentRecordingStartDate
            ?? recordingViewModel.currentMeeting?.date else {
            return segments
        }
        let lower = startedAt.map { $0.timeIntervalSince(recordingStart) } ?? -.infinity
        let upper = endedAt.map { $0.timeIntervalSince(recordingStart) } ?? .infinity
        return segments.filter { $0.startTime >= lower && $0.startTime <= upper }
    }

    // MARK: - Bookmarks

    func addBookmark(type: BookmarkType, note: String? = nil) {
        let bookmark = InterviewBookmark(
            type: type,
            timestamp: recordingViewModel.elapsedTime,
            note: note
        )
        bookmark.interview = interview
        bookmarks.append(bookmark)
    }

    // MARK: - Notes

    func addNote(text: String, category: NoteCategory = .general, parent: InterviewNote? = nil) {
        let note = InterviewNote(text: text, category: category, sortOrder: notes.count)
        note.interview = interview
        note.parentNote = parent
        if let parent {
            parent.subNotes.append(note)
        }
        notes.append(note)
    }

    func deleteNote(_ note: InterviewNote) {
        notes.removeAll { $0.id == note.id }
        // Sub-notes cascade via SwiftData
    }

    /// Tab: indent a note — make it a child of the previous sibling at the same level.
    func indentNote(_ note: InterviewNote) {
        let siblings: [InterviewNote]
        if let parent = note.parentNote {
            siblings = parent.subNotes.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            siblings = notes.filter { $0.parentNote == nil }.sorted { $0.sortOrder < $1.sortOrder }
        }
        guard let idx = siblings.firstIndex(where: { $0.id == note.id }), idx > 0 else { return }
        let newParent = siblings[idx - 1]

        // Detach from current parent
        note.parentNote?.subNotes.removeAll { $0.id == note.id }
        note.parentNote = newParent
        note.sortOrder = newParent.subNotes.count
        newParent.subNotes.append(note)
    }

    /// Shift+Tab: dedent a note — move it up to its grandparent level, after its current parent.
    func dedentNote(_ note: InterviewNote) {
        guard let parent = note.parentNote else { return } // already top-level
        let grandparent = parent.parentNote

        // Remove from current parent
        parent.subNotes.removeAll { $0.id == note.id }

        // Insert after parent at grandparent level
        note.parentNote = grandparent
        if let grandparent {
            note.sortOrder = grandparent.subNotes.count
            grandparent.subNotes.append(note)
        } else {
            // Becomes top-level
            note.sortOrder = notes.filter { $0.parentNote == nil }.count
        }
    }

    // MARK: - Impression Updates

    func updateImpression(traitName: String, value: Int) {
        if let idx = impressions.firstIndex(where: { $0.traitName == traitName }) {
            impressions[idx].value = min(max(value, 1), 5)
        }
    }

    // MARK: - Section Score Updates

    func updateInterviewerGrade(sectionID: UUID, grade: LetterGrade?) {
        if let idx = sectionScores.firstIndex(where: { $0.rubricSectionID == sectionID }) {
            sectionScores[idx].interviewerGrade = grade
        }
    }

    func updateInterviewerNotes(sectionID: UUID, notes: String) {
        if let idx = sectionScores.firstIndex(where: { $0.rubricSectionID == sectionID }) {
            sectionScores[idx].interviewerNotes = notes.isEmpty ? nil : notes
        }
    }

    // MARK: - Rubric Analysis Loop

    private func startRubricAnalysis() {
        rubricAnalysisTask = Task { [weak self] in
            guard let self else { return }

            guard let client = try? await AIClientFactory.makeClient() else {
                await MainActor.run {
                    LogManager.shared.log("AI not configured — skipping rubric analysis", category: .ai, level: .warning)
                }
                return
            }

            // Wait 50s before first rubric analysis (offset from standard 30s)
            await self.waitSeconds(50)

            while !Task.isCancelled {
                // Per-cycle: read which phase is active and what its rubric
                // is. If no scored phase is active (intro/conclusion/freeform
                // or no interview), skip this cycle and try again later.
                let cycle: PhaseCycle? = await MainActor.run { self.makePhaseCycle() }

                guard let cycle else {
                    await MainActor.run {
                        self.rubricAnalysisState = .idle
                    }
                    await self.waitSeconds(45)
                    continue
                }

                await MainActor.run {
                    self.rubricAnalysisState = .analyzing
                }

                let service = InterviewIntelligenceService(
                    client: client,
                    rubricContext: cycle.rubricSnapshot,
                    impressionTraits: cycle.traits,
                    candidateContext: cycle.candidateContext,
                    meetingID: cycle.meetingID
                )
                let allSnapshots = await MainActor.run { self.recordingViewModel.snapshotSegments() }
                let phaseSegments = await MainActor.run {
                    self.filterSegments(allSnapshots, between: cycle.startedAt, and: cycle.endedAt)
                }

                do {
                    if let result = try await service.analyzeAgainstRubric(
                        segments: phaseSegments,
                        activeSectionID: cycle.activeSectionID
                    ) {
                        await MainActor.run {
                            // Only apply if we're still on the same phase —
                            // a transition mid-cycle invalidates the result.
                            if self.interview?.activePhase?.id == cycle.phaseID {
                                self.applyAnalysisResult(result, toPhaseID: cycle.phaseID)
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        LogManager.shared.log("Rubric analysis error: \(error.localizedDescription)", category: .ai, level: .error)
                    }
                }

                // Wait 45s before next analysis
                await self.waitSeconds(45)
            }
        }
    }

    /// Per-cycle inputs for the rubric analyzer, captured atomically on the
    /// MainActor so the background task doesn't observe a torn read across
    /// phase transitions.
    private struct PhaseCycle {
        let phaseID: UUID
        let rubricSnapshot: RubricSnapshot
        let traits: [ImpressionTraitSnapshot]
        let candidateContext: CandidateContext?
        let meetingID: UUID?
        let startedAt: Date?
        let endedAt: Date?
        let activeSectionID: UUID?
    }

    private func makePhaseCycle() -> PhaseCycle? {
        guard let interview, let phase = interview.activePhase, let rubric = phase.rubric else {
            return nil
        }
        return PhaseCycle(
            phaseID: phase.id,
            rubricSnapshot: rubric.toSnapshot(),
            traits: impressionTraitSnapshots,
            candidateContext: candidateContextSnapshot,
            meetingID: recordingViewModel.currentMeeting?.id,
            startedAt: phase.startedAt,
            endedAt: phase.endedAt,
            activeSectionID: activeSectionID
        )
    }

    /// Cached candidate context (name, role, extracted resume text). Built
    /// once at interview start so the resume isn't re-read from disk on
    /// every analysis cycle (and so the truncated prompt-cost stays
    /// stable as the resume file is replaced or removed mid-call).
    private var candidateContextSnapshot: CandidateContext?

    private func buildCandidateContextSnapshot() {
        guard let candidate = interview?.candidate else {
            candidateContextSnapshot = nil
            return
        }
        let resumeText: String? = {
            guard let url = candidate.resumeURL else { return nil }
            return ResumeTextExtractor.extractText(from: url)
        }()
        candidateContextSnapshot = CandidateContext(
            name: candidate.name,
            role: candidate.role?.fullDescription,
            resumeText: resumeText
        )
        if let count = resumeText?.count, count > 0 {
            LogManager.shared.log("Resume context loaded for AI prompt (\(count) chars)", category: .ai)
        }
    }

    private func waitSeconds(_ seconds: Int) async {
        for i in (0..<seconds).reversed() {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.rubricAnalysisState = .waiting(secondsRemaining: i)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Apply an analysis result to a specific phase's section scores. The
    /// phase ID disambiguates which phase's scores to update — important
    /// when multiple phases score against the same rubric (e.g., two
    /// coding rounds), or when a phase transition fires between the
    /// analysis call and its result arriving.
    private func applyAnalysisResult(_ result: InterviewAnalysisResult, toPhaseID phaseID: UUID) {
        guard let interview,
              let phase = interview.phases.first(where: { $0.id == phaseID }) else { return }
        let phaseScores = phase.sectionScores

        for aiScore in result.sectionScores {
            guard let target = phaseScores.first(where: { $0.rubricSectionID == aiScore.sectionID }) else { continue }
            if let gradeStr = aiScore.grade {
                target.aiGrade = LetterGrade(rawValue: gradeStr)
            }
            target.aiConfidence = aiScore.confidence
            target.aiRationale = aiScore.rationale

            // Store legacy JSON evidence for backward compat
            let quoteStrings = aiScore.evidence.map(\.quote)
            if let evidenceData = try? JSONSerialization.data(withJSONObject: quoteStrings),
               let evidenceStr = String(data: evidenceData, encoding: .utf8) {
                target.aiEvidence = evidenceStr
            }

            // Replace evidence items (AI updates cumulatively per phase).
            target.evidenceItems.removeAll()
            for ev in aiScore.evidence {
                let strength = EvidenceStrength(rawValue: ev.strength) ?? .moderate
                let item = ScoreEvidence(
                    quote: ev.quote,
                    timestamp: ev.timestamp,
                    criterionSignal: ev.criterion,
                    strength: strength
                )
                item.sectionScore = target
                target.evidenceItems.append(item)
            }
        }

        for aiScore in result.sectionScores {
            criterionEvaluations[aiScore.sectionID] = aiScore.criterionEvaluations
        }

        // Refresh the VM's mirror array if this is the active phase so UI
        // bindings re-render with new grades/evidence.
        if interview.activePhase?.id == phaseID {
            sectionScores = phase.sectionScores.sorted { $0.sortOrder < $1.sortOrder }
        }

        // Apply AI impression ratings (interview-level, not per-phase).
        for aiImpression in result.impressions {
            if let idx = impressions.firstIndex(where: { $0.traitName == aiImpression.trait }) {
                impressions[idx].value = aiImpression.value
            }
        }

        strengths = result.strengths
        weaknesses = result.weaknesses
        redFlags = result.redFlags
        overallAssessment = result.overallAssessment
    }

    // MARK: - Scroll to Transcript

    func scrollTranscriptToTimestamp(_ timestamp: String) {
        guard let seconds = parseTimestampToSeconds(timestamp) else { return }
        let closest = recordingViewModel.segments
            .filter { $0.isFinal }
            .min(by: { abs($0.startTime - seconds) < abs($1.startTime - seconds) })
        scrollToSegmentID = closest?.id
    }

    private func parseTimestampToSeconds(_ ts: String) -> TimeInterval? {
        let cleaned = ts.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = cleaned.split(separator: ":")
        switch parts.count {
        case 2:
            guard let min = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
            return min * 60 + sec
        case 3:
            guard let hr = Double(parts[0]), let min = Double(parts[1]), let sec = Double(parts[2]) else { return nil }
            return hr * 3600 + min * 60 + sec
        default:
            return nil
        }
    }

    // MARK: - Cleanup

    func reset() {
        // completedInterview is NOT cleared here — ContentView reads it during reset
        recordingViewModel.currentSectionTag = nil
        recordingViewModel.currentSectionTagID = nil
        interview = nil
        sectionScores = []
        impressions = []
        bookmarks = []
        notes = []
        strengths = []
        weaknesses = []
        redFlags = []
        overallAssessment = ""
        criterionEvaluations = [:]
        rubricSnapshot = nil
        impressionTraitSnapshots = []
        scrollToSegmentID = nil
        activePhaseID = Self.introID
        rubricAnalysisState = .idle
        rubricAnalysisTask?.cancel()
        rubricAnalysisTask = nil
    }
}
