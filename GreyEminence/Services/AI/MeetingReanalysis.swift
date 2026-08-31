import Foundation
import SwiftData

/// One-meeting AI reanalysis used by the inspector button and the bulk queue.
enum MeetingReanalysis {
    enum Failure: LocalizedError {
        case notConfigured
        case noTranscript
        case emptyResult
        case recording
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "AI not configured. Check Settings."
            case .noTranscript:
                "No transcript segments to analyze."
            case .emptyResult:
                "Analysis returned no results."
            case .recording:
                "Skipped — meeting is still recording."
            case .saveFailed(let message):
                "Reanalysis succeeded but saving failed: \(message)"
            }
        }
    }

    @MainActor
    static func run(
        meeting: Meeting,
        client: any AIClient,
        context: ModelContext,
        scope: InsightScope = .full,
        depth: InsightDepth = .standard
    ) async throws {
        guard meeting.status != .recording else { throw Failure.recording }
        let snapshots: [SegmentSnapshot] = meeting.segments
            .sorted { $0.startTime < $1.startTime }
            .map {
                SegmentSnapshot(
                    speaker: $0.speaker,
                    text: $0.text,
                    formattedTimestamp: $0.formattedTimestamp,
                    isFinal: $0.isFinal
                )
            }
        guard !snapshots.isEmpty else { throw Failure.noTranscript }

        meeting.isAnalyzing = true
        meeting.analysisError = nil
        PersistenceGate.save(context, site: "MeetingReanalysis.start", meetingID: meeting.id)
        defer {
            meeting.isAnalyzing = false
            PersistenceGate.save(context, site: "MeetingReanalysis.finish", meetingID: meeting.id)
        }

        let previous = meeting.latestInsight
        let currentActions = meeting.actionItems.map {
            ParsedActionItem(text: $0.text, assignee: $0.displayAssignee ?? $0.assignee, sourceQuote: nil)
        }
        let service = AIIntelligenceService(
            client: client,
            meetingID: meeting.id,
            suppressedActionItems: meeting.suppressedActionItems,
            suppressedFollowUps: meeting.suppressedFollowUps
        )
        let roster = MeetingRoster.snapshot(for: meeting)
        let screenBlock = ScreenObservationFormatter.finalBlock(for: meeting)
        let vocalCues: String
        if depth == .deepest {
            vocalCues = VocalCueAnnotator.promptBlock(VocalCueAnnotator.cues(for: meeting))
        } else {
            vocalCues = ""
        }

        let maybeResult: AnalysisResult?
        if depth == .standard && scope == .full {
            maybeResult = try await AIUsageContext.attribute(.reanalysis, meetingID: meeting.id) {
                try await service.reanalyze(
                    segments: snapshots,
                    roster: roster,
                    screenObservations: screenBlock,
                    calendarTitle: meeting.analysisTitleHint
                )
            }
        } else {
            maybeResult = try await AIUsageContext.attribute(.reanalysis, meetingID: meeting.id) {
                try await service.analyzeSection(
                    segments: snapshots,
                    roster: roster,
                    screenObservations: screenBlock,
                    calendarTitle: meeting.analysisTitleHint,
                    scope: scope,
                    depth: depth == .standard ? .deep : depth,
                    currentSummary: previous?.summary ?? "[]",
                    currentActionItems: currentActions,
                    currentFollowUps: previous?.followUpQuestions ?? [],
                    currentTopics: previous?.topics ?? [],
                    vocalCues: vocalCues
                )
            }
        }
        guard let rawResult = maybeResult else { throw Failure.emptyResult }

        let suppressedActions = Set(meeting.suppressedActionItems)
        let suppressedQuestions = Set(meeting.suppressedFollowUps)
        let parsed = AnalysisResult(
            title: rawResult.title,
            summary: rawResult.summary,
            actionItems: rawResult.actionItems.filter { !suppressedActions.contains(normalizeKey($0.text)) },
            followUps: rawResult.followUps.filter { !suppressedQuestions.contains(normalizeKey($0)) },
            topics: rawResult.topics,
            rawResponse: rawResult.rawResponse
        )
        let result = overlay(parsed, onto: previous, scope: scope)

        if scope == .full, let title = result.title {
            meeting.applyGeneratedTitle(title)
        }

        let insight = MeetingInsight(
            summary: result.summary,
            followUpQuestions: result.followUps,
            topics: result.topics,
            rawLLMResponse: result.rawResponse,
            modelIdentifier: client.modelIdentifier,
            promptVersion: AIPromptTemplates.promptVersion,
            scopeRaw: scope.rawValue,
            depthRaw: depth.rawValue,
            actionItemsJSON: InsightRevision.encodeActions(result.actionItems)
                ?? InsightRevision.encodeMeetingActions(meeting.actionItems)
        )
        insight.meeting = meeting
        context.insert(insight)
        if scope == .full || (scope == .actionItems && !result.actionItems.isEmpty) {
            mergeActionItems(parsed: result.actionItems, into: meeting, context: context)
        }

        let saved = PersistenceGate.save(
            context,
            site: "MeetingReanalysis.run",
            critical: true,
            meetingID: meeting.id
        )
        if !saved {
            throw Failure.saveFailed(PersistenceGate.lastFailureMessage ?? "unknown")
        }
        GrokLibrary.upsert(meeting)
    }

    @MainActor
    static func revert(
        meeting: Meeting,
        scope: InsightScope,
        context: ModelContext,
        from insight: MeetingInsight? = nil
    ) throws {
        let current = meeting.latestInsight
        guard let previous = insight ?? InsightRevision.previousInsight(for: meeting, scope: scope, after: current) else {
            throw Failure.emptyResult
        }
        var summary = current?.summary ?? previous.summary
        var followUps = current?.followUpQuestions ?? previous.followUpQuestions
        var topics = current?.topics ?? previous.topics
        switch scope {
        case .full:
            summary = previous.summary
            followUps = previous.followUpQuestions
            topics = previous.topics
            let restored = InsightRevision.decodeActions(previous.actionItemsJSON)
            if !restored.isEmpty {
                mergeActionItems(parsed: restored, into: meeting, context: context)
            }
        case .summary:
            summary = previous.summary
        case .followUps:
            followUps = previous.followUpQuestions
        case .topics:
            topics = previous.topics
        case .actionItems:
            let restored = InsightRevision.decodeActions(previous.actionItemsJSON)
            if !restored.isEmpty {
                mergeActionItems(parsed: restored, into: meeting, context: context)
            }
        }
        let restoredInsight = MeetingInsight(
            summary: summary,
            followUpQuestions: followUps,
            topics: topics,
            rawLLMResponse: previous.rawLLMResponse,
            modelIdentifier: previous.modelIdentifier,
            promptVersion: previous.promptVersion,
            scopeRaw: scope.rawValue,
            depthRaw: InsightDepth.revert.rawValue,
            actionItemsJSON: previous.actionItemsJSON
        )
        restoredInsight.meeting = meeting
        context.insert(restoredInsight)
        let saved = PersistenceGate.save(
            context,
            site: "MeetingReanalysis.revert",
            critical: true,
            meetingID: meeting.id
        )
        if !saved {
            throw Failure.saveFailed(PersistenceGate.lastFailureMessage ?? "unknown")
        }
    }

    private static func overlay(
        _ parsed: AnalysisResult,
        onto previous: MeetingInsight?,
        scope: InsightScope
    ) -> AnalysisResult {
        guard let previous, scope != .full else { return parsed }
        let summaryEmpty = parsed.summary.isEmpty || parsed.summary == "[]"
        return AnalysisResult(
            title: parsed.title,
            summary: (scope == .summary && !summaryEmpty) ? parsed.summary : previous.summary,
            actionItems: scope == .actionItems && !parsed.actionItems.isEmpty
                ? parsed.actionItems
                : InsightRevision.decodeActions(previous.actionItemsJSON),
            followUps: (scope == .followUps && !parsed.followUps.isEmpty)
                ? parsed.followUps
                : previous.followUpQuestions,
            topics: (scope == .topics && !parsed.topics.isEmpty) ? parsed.topics : previous.topics,
            rawResponse: parsed.rawResponse
        )
    }

    static func normalizeKey(_ text: String) -> String {
        let lowered = text.lowercased()
        let collapsed = lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,;:"))
    }

    @MainActor
    static func mergeActionItems(
        parsed: [ParsedActionItem],
        into meeting: Meeting,
        context: ModelContext
    ) {
        let existing = meeting.actionItems
        let existingKeys = Set(existing.map { normalizeKey($0.text) })
        let suppressedKeys = Set(meeting.suppressedActionItems)
        let parsedKeys = Set(parsed.map { normalizeKey($0.text) })
        let stale = existing.filter { item in
            let untouched = !item.isCompleted && item.dueDate == nil && item.assignedContact == nil
            return untouched && !parsedKeys.contains(normalizeKey(item.text))
        }
        for item in stale { context.delete(item) }
        for parsedItem in parsed {
            let key = normalizeKey(parsedItem.text)
            guard !existingKeys.contains(key), !suppressedKeys.contains(key) else { continue }
            let item = ActionItem(parsed: parsedItem, sourceSegments: meeting.segments)
            item.meeting = meeting
            context.insert(item)
        }
    }

    @MainActor
    static func eligibleIDs(in context: ModelContext, restrictingTo ids: Set<UUID>? = nil) -> [UUID] {
        let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let meetings = (try? context.fetch(descriptor)) ?? []
        return meetings.compactMap { meeting in
            if meeting.isInterviewMeeting { return nil }
            if meeting.status == .recording || meeting.status == .paused { return nil }
            if meeting.segments.isEmpty { return nil }
            if let ids, !ids.contains(meeting.id) { return nil }
            return meeting.id
        }
    }
}

@MainActor
@Observable
final class MeetingReanalysisQueue {
    static let shared = MeetingReanalysisQueue()

    struct Job: Equatable {
        var title: String
        var index: Int
        var total: Int
    }

    struct Failure: Identifiable, Equatable {
        let id: UUID
        let meetingID: UUID?
        let title: String
        let date: Date
        let message: String
    }

    private(set) var pending: [UUID] = []
    private(set) var current: Job?
    private(set) var currentID: UUID?
    private(set) var lastError: String?
    private(set) var lastSummary: String?
    private(set) var failures: [Failure] = []
    private(set) var completedCount = 0
    private(set) var failedCount = 0
    private var worker: Task<Void, Never>?
    private var context: ModelContext?

    var isRunning: Bool { current != nil || !pending.isEmpty }

    func contains(_ id: UUID) -> Bool {
        currentID == id || pending.contains(id)
    }

    func enqueue(ids: [UUID], in context: ModelContext) {
        self.context = context
        let wasIdle = !isRunning
        for id in ids where !contains(id) {
            pending.append(id)
        }
        if wasIdle {
            completedCount = 0
            failedCount = 0
            lastError = nil
            lastSummary = nil
            failures = []
        }
        DevLog.ui("reanalyze-queue enqueue \(ids.count) meeting(s), pending=\(pending.count)")
        pumpIfNeeded()
    }

    func enqueueEligible(in context: ModelContext, restrictingTo ids: Set<UUID>? = nil) {
        enqueue(ids: MeetingReanalysis.eligibleIDs(in: context, restrictingTo: ids), in: context)
    }

    func cancel() {
        worker?.cancel()
        pending.removeAll()
        current = nil
        currentID = nil
        lastSummary = nil
        DevLog.ui("reanalyze-queue cancelled")
    }

    func cancelMeeting(_ id: UUID) {
        pending.removeAll { $0 == id }
        if currentID == id {
            worker?.cancel()
        }
        DevLog.ui("reanalyze-queue cancel meeting \(id)")
    }

    func dismissBanner() {
        lastError = nil
        lastSummary = nil
        failures = []
        failedCount = 0
    }

    private func pumpIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.runLoop()
            self?.worker = nil
            self?.pumpIfNeeded()
        }
    }

    private func runLoop() async {
        guard let client = try? await AIClientFactory.makeClient() else {
            let message = MeetingReanalysis.Failure.notConfigured.localizedDescription
            lastError = message
            failures.append(
                Failure(
                    id: UUID(),
                    meetingID: nil,
                    title: "AI not configured",
                    date: .now,
                    message: message
                )
            )
            failedCount = max(failedCount, 1)
            pending.removeAll()
            current = nil
            currentID = nil
            return
        }
        var index = completedCount + failedCount
        while !Task.isCancelled, !pending.isEmpty {
            let id = pending.removeFirst()
            index += 1
            guard let context, let meeting = fetch(id, in: context) else { continue }
            currentID = id
            current = Job(
                title: meeting.title,
                index: index,
                total: max(index + pending.count, index)
            )
            do {
                try await MeetingReanalysis.run(meeting: meeting, client: client, context: context)
                completedCount += 1
                DevLog.ui("reanalyze-queue ok \(meeting.title)")
            } catch is CancellationError {
                meeting.isAnalyzing = false
                PersistenceGate.save(context, site: "MeetingReanalysisQueue.cancel", meetingID: id)
                break
            } catch {
                let message = error.localizedDescription
                failedCount += 1
                lastError = message
                failures.append(
                    Failure(
                        id: UUID(),
                        meetingID: meeting.id,
                        title: meeting.title,
                        date: meeting.date,
                        message: message
                    )
                )
                meeting.analysisError = message
                meeting.isAnalyzing = false
                PersistenceGate.save(context, site: "MeetingReanalysisQueue.fail", meetingID: id)
                DevLog.ui("reanalyze-queue fail \(meeting.title): \(message)", level: .error)
            }
        }
        current = nil
        currentID = nil
        if !Task.isCancelled, pending.isEmpty, completedCount + failedCount > 0 {
            if failedCount == 0 {
                lastSummary = completedCount == 1
                    ? "Reanalyzed 1 meeting"
                    : "Reanalyzed \(completedCount) meetings"
            } else if completedCount > 0 {
                lastSummary = "Reanalyzed \(completedCount), \(failedCount) failed"
            }
        }
    }

    private func fetch(_ id: UUID, in context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
