import Foundation
import SwiftData

/// Runs idempotent retroactive cleanup tasks at app launch on a background-
/// priority Task. Each cleanup detects and repairs a class of inconsistency
/// the audit found in production data: orphan embeddings, stale segment
/// embeddings from re-processing, stuck `isAnalyzing` flags, action items
/// that predate `sourceSegmentID` resolution, etc.
///
/// The whole pass is throttled to once per 24 h via UserDefaults so it
/// doesn't repeatedly scan tens of thousands of records on quick relaunches.
@MainActor
enum MaintenanceService {
    private static let lastRunKey = "maintenanceLastRunAt"
    private static let throttleInterval: TimeInterval = 24 * 60 * 60

    struct Report {
        var orphanEmbeddingsRemoved = 0
        var staleSegmentEmbeddingsRemoved = 0
        var stuckAnalyzingFlagsReset = 0
        var actionItemsBackfilled = 0
        var interviewsBackfilledToPhases = 0
        var criterionGuidanceBackfilled = 0
        var roleRubricLinksBackfilled = 0
        var usageEventsPruned = 0
        var skipped = false

        var summary: String {
            if skipped { return "Maintenance skipped (ran within last 24h)" }
            return """
            Maintenance complete: \
            \(orphanEmbeddingsRemoved) orphan embedding(s) removed, \
            \(staleSegmentEmbeddingsRemoved) stale segment embedding(s) removed, \
            \(stuckAnalyzingFlagsReset) stuck analysis flag(s) cleared, \
            \(actionItemsBackfilled) action item source(s) backfilled, \
            \(interviewsBackfilledToPhases) legacy interview(s) wrapped in phases, \
            \(criterionGuidanceBackfilled) evaluation note(s) migrated to guidance bullets, \
            \(roleRubricLinksBackfilled) rubric→role link(s) backfilled, \
            \(usageEventsPruned) old AI usage event(s) pruned
            """
        }
    }

    /// Public entry point. Caller is responsible for running this on a
    /// `Task(priority: .background)` — the work itself is MainActor-bound
    /// because it mutates SwiftData, but a low-priority Task ensures it
    /// yields to interactive UI and any in-flight recording work.
    /// Named steps, so the status bar can say which one is running rather
    /// than sitting on "Running startup maintenance…" for the duration.
    private static let stepNames = [
        "Removing orphaned search entries",
        "Pruning stale transcript entries",
        "Clearing stuck analysis flags",
        "Linking tasks to their quotes",
        "Updating interview records",
        "Updating scoring guidance",
        "Linking roles to rubrics",
        "Trimming the usage log",
    ]

    /// Runs on the main actor because it mutates SwiftData, but yields
    /// between and within steps.
    ///
    /// It used to run straight through: faulting every segment of every
    /// meeting, walking tens of thousands of embedding records, without ever
    /// handing the run loop back. The status bar said what was happening and
    /// the window was frozen solid while it said it — which is worse than
    /// silence, because it looks like the app is working when it is unusable.
    @discardableResult
    static func runStartupMaintenance(
        modelContext: ModelContext,
        force: Bool = false,
        onStep: (@MainActor (Int, Int, String) -> Void)? = nil
    ) async -> Report {
        var report = Report()
        if !force, let last = lastRunDate(), Date().timeIntervalSince(last) < throttleInterval {
            report.skipped = true
            return report
        }

        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let liveMeetingIDs = Set(meetings.map(\.id))
        let total = stepNames.count

        func step(_ index: Int) async {
            onStep?(index, total, stepNames[index])
            await Task.yield()
        }

        await step(0)
        report.orphanEmbeddingsRemoved = pruneOrphanEmbeddings(liveMeetingIDs: liveMeetingIDs)
        await step(1)
        report.staleSegmentEmbeddingsRemoved = await pruneStaleSegmentEmbeddings(meetings: meetings)
        await step(2)
        report.stuckAnalyzingFlagsReset = await resetStuckAnalyzingFlags(meetings: meetings, in: modelContext)
        await step(3)
        report.actionItemsBackfilled = await backfillActionItemSources(meetings: meetings, in: modelContext)
        await step(4)
        report.interviewsBackfilledToPhases = backfillInterviewPhases(in: modelContext)
        await step(5)
        report.criterionGuidanceBackfilled = backfillCriterionGuidance(in: modelContext)
        await step(6)
        report.roleRubricLinksBackfilled = backfillRoleRubricLinks(in: modelContext)
        await step(7)
        report.usageEventsPruned = pruneOldUsageEvents(in: modelContext)
        onStep?(total, total, "")

        UserDefaults.standard.set(Date(), forKey: lastRunKey)
        LogManager.send(report.summary, category: .general)
        return report
    }

    private static func lastRunDate() -> Date? {
        UserDefaults.standard.object(forKey: lastRunKey) as? Date
    }

    // MARK: - Cleanups

    /// Drop embeddings whose meetingID no longer points at a live meeting —
    /// the legacy of pre-fix MeetingDeletion not pruning the embedding store.
    private static func pruneOrphanEmbeddings(liveMeetingIDs: Set<UUID>) -> Int {
        guard let store = EmbeddingStore.shared else { return 0 }
        return store.deleteRecords(notMatchingMeetingIDs: liveMeetingIDs)
    }

    /// Drop transcript-chunk embeddings whose `sourceID` (the first segment
    /// of the chunk) no longer matches any segment in the meeting. Happens
    /// when re-processing replaced segments without first dropping the old
    /// chunks (fixed going forward but historical data is poisoned).
    private static func pruneStaleSegmentEmbeddings(meetings: [Meeting]) async -> Int {
        guard let store = EmbeddingStore.shared else { return 0 }
        let context = store.context
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.sourceKindRaw == "transcriptSegment" }
        )
        guard let records = try? context.fetch(descriptor) else { return 0 }

        // Grouped by meeting so each one's segments are faulted once, checked,
        // and then the run loop gets a turn. Building the whole map up front
        // pulled several hundred thousand segments into memory before a single
        // record was examined.
        var recordsByMeeting: [UUID: [EmbeddingRecord]] = [:]
        for record in records {
            recordsByMeeting[record.meetingID, default: []].append(record)
        }
        let meetingsByID = Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0) })

        var pruned = 0
        for (index, (meetingID, meetingRecords)) in recordsByMeeting.enumerated() {
            if index % 10 == 0 { await Task.yield() }
            let liveSegmentIDs = meetingsByID[meetingID].map { Set($0.segments.map(\.id)) } ?? []
            for record in meetingRecords where !liveSegmentIDs.contains(record.sourceID) {
                context.delete(record)
                pruned += 1
            }
        }
        if pruned > 0 { store.save() }
        return pruned
    }

    /// Reset `isAnalyzing` on meetings that already have a final insight —
    /// they were stuck because an exception path forgot to clear the flag
    /// (e.g. a thrown `analyzeMeetingAfterSplit`). We also clear it if the
    /// meeting hasn't been touched in over an hour and there's no analysis
    /// in flight that could possibly be tracking it.
    private static func resetStuckAnalyzingFlags(meetings: [Meeting], in context: ModelContext) async -> Int {
        let staleThreshold: TimeInterval = 60 * 60
        let now = Date()
        var reset = 0
        // `isAnalyzing` is a stored property so the filter is cheap, but each
        // survivor faults its insights — yield so a library-wide sweep can't
        // hold the run loop.
        for (index, meeting) in meetings.enumerated() where meeting.isAnalyzing {
            if index % 25 == 0 { await Task.yield() }
            let hasInsight = !meeting.insights.isEmpty
            let isAged = now.timeIntervalSince(meeting.date) > staleThreshold
            if hasInsight || isAged {
                meeting.isAnalyzing = false
                reset += 1
            }
        }
        if reset > 0 {
            PersistenceGate.save(context, site: "Maintenance.resetStuckAnalyzing")
        }
        return reset
    }

    /// Action items created before the source-quote pipeline shipped have
    /// `sourceSegmentID == nil`. Best-effort backfill: feed the action item's
    /// own text through the same matching helper. The helper requires either
    /// a substring match or ≥3 token overlap, so spurious matches are rare —
    /// when no segment is plausibly related, sourceSegmentID stays nil and
    /// the task detail just doesn't show conversation context.
    private static func backfillActionItemSources(meetings: [Meeting], in context: ModelContext) async -> Int {
        var backfilled = 0
        for (index, meeting) in meetings.enumerated() {
            if index % 10 == 0 { await Task.yield() }
            // Only meetings with an unlinked item touch their segments at all.
            guard meeting.actionItems.contains(where: { $0.sourceSegmentID == nil }) else { continue }
            for item in meeting.actionItems where item.sourceSegmentID == nil {
                if let id = meeting.segments.segmentID(matchingQuote: item.text) {
                    item.sourceSegmentID = id
                    backfilled += 1
                }
            }
        }
        if backfilled > 0 {
            PersistenceGate.save(context, site: "Maintenance.backfillActionItemSources")
        }
        return backfilled
    }

    /// Wraps legacy single-rubric interviews in a single-phase tree so the
    /// new phase-shaped UI can read them. An interview is "legacy" when its
    /// `phases` array is empty but it has either a `rubric` or
    /// `sectionScores` from before phase support shipped.
    ///
    /// The synthesized phase covers the meeting's full duration (so the AI
    /// loop's "segments since phase start" filter degenerates to "all
    /// segments" for legacy data) and is marked `.completed` so the live
    /// transition UI doesn't try to re-activate it.
    private static func backfillInterviewPhases(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Interview>()
        guard let interviews = try? context.fetch(descriptor) else { return 0 }
        var backfilled = 0
        for interview in interviews where interview.phases.isEmpty {
            let hasLegacyData = interview.rubric != nil || !interview.sectionScores.isEmpty
            guard hasLegacyData else { continue }

            let phaseTitle = interview.rubric?.name ?? "Interview"
            let phase = InterviewPhase(
                title: phaseTitle,
                rubric: interview.rubric,
                plannedOrder: 0,
                status: .completed
            )
            phase.startedAt = interview.meeting?.date ?? interview.createdAt
            phase.endedAt = interview.meeting.map { $0.date.addingTimeInterval($0.duration) } ?? .now
            phase.interview = interview
            interview.phases.append(phase)

            for score in interview.sectionScores where score.phase == nil {
                score.phase = phase
                phase.sectionScores.append(score)
            }
            backfilled += 1
        }
        if backfilled > 0 {
            PersistenceGate.save(context, site: "Maintenance.backfillInterviewPhases")
        }
        return backfilled
    }

    /// Migrate legacy `RubricCriterion.evaluationNotes` into a single
    /// `CriterionGuidance` bullet (audience: interviewer). Idempotent —
    /// once a criterion has any guidance, this leaves it alone.
    private static func backfillCriterionGuidance(in context: ModelContext) -> Int {
        // Only fetch criteria that actually have legacy notes — a rubric
        // with hundreds of clean criteria shouldn't materialize them all.
        let descriptor = FetchDescriptor<RubricCriterion>(
            predicate: #Predicate { $0.evaluationNotes != nil }
        )
        guard let criteria = try? context.fetch(descriptor) else { return 0 }
        var backfilled = 0
        for criterion in criteria {
            guard let notes = criterion.evaluationNotes,
                  !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  criterion.guidance.isEmpty else { continue }
            let guidance = CriterionGuidance(
                text: notes,
                audience: .interviewer,
                sortOrder: 0
            )
            guidance.criterion = criterion
            criterion.guidance.append(guidance)
            backfilled += 1
        }
        if backfilled > 0 {
            PersistenceGate.save(context, site: "Maintenance.backfillCriterionGuidance")
        }
        return backfilled
    }

    /// Drop AI usage-ledger events older than 90 days — the settings pane
    /// shows 30-day totals, so anything past 90 is dead weight.
    private static func pruneOldUsageEvents(in context: ModelContext) -> Int {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<AIUsageEvent>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return 0 }
        for event in stale {
            context.delete(event)
        }
        PersistenceGate.save(context, site: "Maintenance.pruneUsageEvents")
        return stale.count
    }

    /// Synthesize one `RoleRubricLink` for every rubric that has the
    /// legacy `role` pointer but no `roleLinks`. Idempotent.
    private static func backfillRoleRubricLinks(in context: ModelContext) -> Int {
        // Only fetch rubrics that have a legacy role pointer — rubrics
        // with role == nil have nothing to migrate.
        let descriptor = FetchDescriptor<Rubric>(
            predicate: #Predicate { $0.role != nil }
        )
        guard let rubrics = try? context.fetch(descriptor) else { return 0 }
        var backfilled = 0
        for rubric in rubrics {
            guard let role = rubric.role, rubric.roleLinks.isEmpty else { continue }
            let link = RoleRubricLink(
                rubric: rubric,
                role: role,
                strictness: .standard,
                sortOrder: 0
            )
            context.insert(link)
            rubric.roleLinks.append(link)
            backfilled += 1
        }
        if backfilled > 0 {
            PersistenceGate.save(context, site: "Maintenance.backfillRoleRubricLinks")
        }
        return backfilled
    }
}
