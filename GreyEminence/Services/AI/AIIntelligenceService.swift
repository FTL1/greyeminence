import Foundation

// MARK: - Lightweight Sendable Snapshot Types

struct SegmentSnapshot: Sendable, Codable {
    let speaker: Speaker
    let text: String
    let formattedTimestamp: String
    let isFinal: Bool
    /// Seconds elapsed since the recording started. Used by interview phase
    /// scoping to bound analysis to a phase's time window.
    var startTime: TimeInterval = 0
}

struct AnalysisResult: Sendable {
    let title: String?
    let summary: String          // JSON-encoded [SummarySection], or legacy "- bullet" string
    let actionItems: [ParsedActionItem]
    let followUps: [String]
    let topics: [String]
    /// Raw text returned by the model, kept alongside the parsed result so callers
    /// can persist it for debugging / replay. Present whenever parsing succeeded.
    let rawResponse: String
}

struct ParsedActionItem: Sendable {
    let text: String
    let assignee: String?
    /// Verbatim transcript snippet used to anchor the item to a source segment.
    let sourceQuote: String?
}

/// Who's in the meeting, from the tool user's perspective. Grounds the
/// action-item ownership rules: the tool serves one user, so items another
/// attendee owns are excluded — except in a 1:1, where the other person's
/// commitments are promises to the user.
struct MeetingRoster: Sendable {
    let myName: String?
    let otherAttendees: [String]
    /// Extra names that still mean the local user (session/global display name).
    let myAliases: [String]

    var isOneOnOne: Bool { otherAttendees.count == 1 }

    init(myName: String?, otherAttendees: [String], myAliases: [String] = []) {
        self.myName = myName
        self.otherAttendees = otherAttendees
        self.myAliases = myAliases
    }

    /// Snapshot from a meeting's attendee list, with "me" resolved via the
    /// My Profile contact. Taken fresh at each analysis pass because the
    /// attendee list can change mid-recording (calendar link/unlink).
    @MainActor
    static func snapshot(for meeting: Meeting) -> MeetingRoster {
        let myID = Meeting.storedMyContactID
        let contactName = meeting.attendees.first { $0.id == myID }?.name
        let aliases = [SpeakerNames.effectiveMeName].compactMap { $0 }
        return MeetingRoster(
            myName: contactName ?? SpeakerNames.effectiveMeName,
            otherAttendees: meeting.attendees.filter { $0.id != myID }.map(\.name),
            myAliases: aliases
        )
    }
}

// MARK: - Structured Summary Types

struct SummaryPoint: Sendable, Codable, Equatable {
    var label: String
    var detail: String
}

struct SummarySection: Sendable, Codable, Equatable {
    var title: String
    var intro: String?
    var points: [SummaryPoint]

    static func encode(_ sections: [SummarySection]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sections) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension SummarySection {
    /// Parse a stored summary string into structured sections.
    /// Returns nil for legacy flat-string summaries (backward compat).
    static func parse(_ raw: String) -> [SummarySection]? {
        guard raw.hasPrefix("["),
              let data = raw.data(using: .utf8),
              let sections = try? JSONDecoder().decode([SummarySection].self, from: data),
              !sections.isEmpty else {
            return nil
        }
        return sections
    }
}

// MARK: - Intelligence Service

actor AIIntelligenceService {
    /// Called with the meeting's accumulated topics at final-analysis time;
    /// returns formatted transcript snippets from other meetings (or nil) used
    /// to ground blind-spot follow-up questions.
    typealias RelatedContextProvider = @Sendable ([String]) async -> String?

    private let client: any AIClient
    private let prepContext: MeetingPrepContext?
    private let meetingID: UUID?
    private let suppressedActionItems: [String]
    private let suppressedFollowUps: [String]
    private let relatedContextProvider: RelatedContextProvider?
    private var previousSummary: String = ""
    private var previousActionItems: [ParsedActionItem] = []
    private var previousFollowUps: [String] = []
    private var previousTopics: [String] = []
    private var lastAnalyzedSegmentCount: Int = 0

    init(
        client: any AIClient,
        prepContext: MeetingPrepContext? = nil,
        meetingID: UUID? = nil,
        suppressedActionItems: [String] = [],
        suppressedFollowUps: [String] = [],
        relatedContextProvider: RelatedContextProvider? = nil
    ) {
        self.client = client
        self.prepContext = prepContext
        self.meetingID = meetingID
        self.suppressedActionItems = suppressedActionItems
        self.suppressedFollowUps = suppressedFollowUps
        self.relatedContextProvider = relatedContextProvider
    }

    private func effectiveSystemPrompt(roster: MeetingRoster?) -> String {
        AIPromptTemplates.systemPromptWithContext(prep: prepContext, roster: roster)
    }

    /// `screenObservations` is a pre-rendered block of screen-share
    /// observations (new-since-last-pass for rolling calls) — appended after
    /// the rendered template so user prompt overrides keep working untouched.
    func analyze(segments: [SegmentSnapshot], roster: MeetingRoster? = nil, screenObservations: String? = nil) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard nonEmpty.count > lastAnalyzedSegmentCount else {
            return nil
        }

        let newSegments = Array(nonEmpty.dropFirst(lastAnalyzedSegmentCount))
        guard !newSegments.isEmpty else { return nil }

        let transcript: String
        var userPrompt: String

        if previousSummary.isEmpty {
            transcript = AIPromptTemplates.formatSegments(Array(nonEmpty))
            userPrompt = AIPromptTemplates.initialAnalysisPrompt(transcript: transcript)
        } else {
            transcript = AIPromptTemplates.formatSegments(newSegments)
            userPrompt = AIPromptTemplates.rollingAnalysisPrompt(
                previousSummary: previousSummary,
                previousActionItems: previousActionItems,
                previousFollowUps: previousFollowUps,
                previousTopics: previousTopics,
                newTranscript: transcript,
                suppressedActionItems: suppressedActionItems,
                suppressedFollowUps: suppressedFollowUps
            )
        }
        userPrompt += AIPromptTemplates.screenObservationBlock(screenObservations)

        LogManager.send("AI analysis starting (\(nonEmpty.count) segments)", category: .ai, meetingID: meetingID)
        let capturedMeetingID = meetingID
        let purpose: AIUsagePurpose = previousSummary.isEmpty ? .transcriptInitial : .transcriptRolling
        let systemPrompt = effectiveSystemPrompt(roster: roster)
        let response = try await AIUsageContext.attribute(purpose, meetingID: capturedMeetingID) {
            try await AIRetry.run(label: "analyze", meetingID: capturedMeetingID) { [client, systemPrompt, userPrompt] in
                try await withTimeout(seconds: AIClientFactory.analysisTimeoutSeconds) {
                    try await client.sendMessage(
                        system: systemPrompt,
                        userContent: userPrompt
                    )
                }
            }
        }
        LogManager.send("AI raw response (\(response.count) chars): \(response.prefix(500))", category: .ai, meetingID: meetingID)

        let parsed = try parseResponse(response, raw: response)
        let result = applyResultPreservingPrevious(parsed)
        previousSummary = result.summary
        previousActionItems = result.actionItems
        previousFollowUps = result.followUps
        previousTopics = result.topics
        lastAnalyzedSegmentCount = nonEmpty.count
        LogManager.send("AI analysis complete", category: .ai, meetingID: meetingID)
        return result
    }

    /// Guard against a structurally-valid response that ships an empty
    /// summary array overwriting non-empty accumulated state. Claude
    /// occasionally returns `{"summary": []}` for short delta passes; we'd
    /// rather keep the prior pass's summary than wipe the user's screen.
    private func applyResultPreservingPrevious(_ parsed: AnalysisResult) -> AnalysisResult {
        let isEmptySummary = parsed.summary.isEmpty || parsed.summary == "[]"
        guard isEmptySummary, !previousSummary.isEmpty else { return parsed }
        LogManager.send("AI returned empty summary — keeping previous accumulated state", category: .ai, level: .warning, meetingID: meetingID)
        return AnalysisResult(
            title: parsed.title,
            summary: previousSummary,
            actionItems: parsed.actionItems.isEmpty ? previousActionItems : parsed.actionItems,
            followUps: parsed.followUps.isEmpty ? previousFollowUps : parsed.followUps,
            topics: parsed.topics.isEmpty ? previousTopics : parsed.topics,
            rawResponse: parsed.rawResponse
        )
    }

    /// Full-transcript rewrite used by Reanalyze. Ignores rolling state and
    /// does not see prior insights — the point is to throw away a first pass
    /// that latched onto calendar subject / shared-document topic.
    func reanalyze(
        segments: [SegmentSnapshot],
        roster: MeetingRoster? = nil,
        screenObservations: String? = nil,
        calendarTitle: String? = nil
    ) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        let transcript = AIPromptTemplates.formatSegments(nonEmpty)
        var userPrompt = AIPromptTemplates.reanalysisPrompt(
            transcript: transcript,
            calendarTitle: calendarTitle ?? "",
            myName: roster?.myName,
            suppressedActionItems: suppressedActionItems,
            suppressedFollowUps: suppressedFollowUps
        )
        userPrompt += AIPromptTemplates.screenObservationBlock(screenObservations)

        LogManager.send("AI reanalysis starting (\(nonEmpty.count) segments)", category: .ai, meetingID: meetingID)
        let capturedMeetingID = meetingID
        let systemPrompt = effectiveSystemPrompt(roster: roster)
        let response = try await AIUsageContext.attribute(.reanalysis, meetingID: capturedMeetingID) {
            try await AIRetry.run(label: "reanalyze", meetingID: capturedMeetingID) { [client, systemPrompt, userPrompt] in
                try await withTimeout(seconds: AIClientFactory.analysisTimeoutSeconds) {
                    try await client.sendMessage(
                        system: systemPrompt,
                        userContent: userPrompt
                    )
                }
            }
        }
        LogManager.send("AI reanalysis raw response (\(response.count) chars): \(response.prefix(500))", category: .ai, meetingID: meetingID)

        let parsed = try parseResponse(response, raw: response)
        LogManager.send("AI reanalysis complete", category: .ai, meetingID: meetingID)
        return parsed
    }

    func analyzeSection(
        segments: [SegmentSnapshot],
        roster: MeetingRoster? = nil,
        screenObservations: String? = nil,
        calendarTitle: String? = nil,
        scope: InsightScope,
        depth: InsightDepth,
        currentSummary: String,
        currentActionItems: [ParsedActionItem],
        currentFollowUps: [String],
        currentTopics: [String],
        vocalCues: String = ""
    ) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        let transcript = AIPromptTemplates.formatSegments(nonEmpty)
        var userPrompt = AIPromptTemplates.sectionAnalysisPrompt(
            depth: depth,
            scope: scope,
            transcript: transcript,
            calendarTitle: calendarTitle ?? "",
            myName: roster?.myName,
            currentSummary: currentSummary,
            currentActionItems: currentActionItems,
            currentFollowUps: currentFollowUps,
            currentTopics: currentTopics,
            vocalCues: vocalCues,
            suppressedActionItems: suppressedActionItems,
            suppressedFollowUps: suppressedFollowUps
        )
        userPrompt += AIPromptTemplates.screenObservationBlock(screenObservations)

        LogManager.send(
            "AI \(depth.rawValue) \(scope.rawValue) starting (\(nonEmpty.count) segments)",
            category: .ai,
            meetingID: meetingID
        )
        let capturedMeetingID = meetingID
        let systemPrompt = effectiveSystemPrompt(roster: roster)
        let response = try await AIUsageContext.attribute(.reanalysis, meetingID: capturedMeetingID) {
            try await AIRetry.run(label: "section-\(depth.rawValue)", meetingID: capturedMeetingID) { [client, systemPrompt, userPrompt] in
                try await withTimeout(seconds: AIClientFactory.analysisTimeoutSeconds) {
                    try await client.sendMessage(system: systemPrompt, userContent: userPrompt)
                }
            }
        }
        LogManager.send(
            "AI \(depth.rawValue) \(scope.rawValue) raw response (\(response.count) chars)",
            category: .ai,
            meetingID: meetingID
        )
        return try parseResponse(response, raw: response)
    }

    /// `screenObservations` is the full session-grouped observation block for
    /// the meeting (see `ScreenObservationFormatter.finalBlock`).
    func performFinalAnalysis(
        segments: [SegmentSnapshot],
        roster: MeetingRoster? = nil,
        screenObservations: String? = nil,
        calendarTitle: String? = nil
    ) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        // Single final pass with the full transcript. If we have prior accumulated
        // context, use the cleanup prompt; otherwise a purpose-first rewrite.
        guard !previousSummary.isEmpty else {
            return try await reanalyze(
                segments: segments,
                roster: roster,
                screenObservations: screenObservations,
                calendarTitle: calendarTitle
            )
        }

        // Related discussions from other meetings, retrieved with the topics
        // accumulated during rolling analysis. Grounds blind-spot follow-ups;
        // nil (store empty, provider unavailable) degrades to prompt-only.
        var relatedContext: String? = nil
        if let relatedContextProvider {
            relatedContext = await relatedContextProvider(previousTopics)
            if let relatedContext {
                LogManager.send("Related-meeting context attached (\(relatedContext.count) chars)", category: .ai, meetingID: meetingID)
            }
        }

        // Final cleanup pass: send full transcript + all accumulated insights
        let fullTranscript = AIPromptTemplates.formatSegments(nonEmpty)
        var userPrompt = AIPromptTemplates.finalCleanupPrompt(
            fullTranscript: fullTranscript,
            currentSummary: previousSummary,
            currentActionItems: previousActionItems,
            currentFollowUps: previousFollowUps,
            currentTopics: previousTopics,
            suppressedActionItems: suppressedActionItems,
            suppressedFollowUps: suppressedFollowUps,
            relatedContext: relatedContext
        )
        userPrompt += AIPromptTemplates.screenObservationBlock(screenObservations)

        LogManager.send("AI final cleanup starting (\(nonEmpty.count) segments)", category: .ai, meetingID: meetingID)
        let capturedMeetingID = meetingID
        let systemPrompt = effectiveSystemPrompt(roster: roster)
        let response = try await AIUsageContext.attribute(.transcriptFinal, meetingID: capturedMeetingID) {
            try await AIRetry.run(label: "finalCleanup", meetingID: capturedMeetingID) { [client, systemPrompt, userPrompt] in
                try await withTimeout(seconds: AIClientFactory.analysisTimeoutSeconds) {
                    try await client.sendMessage(
                        system: systemPrompt,
                        userContent: userPrompt
                    )
                }
            }
        }
        LogManager.send("AI final cleanup raw response (\(response.count) chars): \(response.prefix(500))", category: .ai, meetingID: meetingID)

        let parsed = try parseResponse(response, raw: response)
        let result = applyResultPreservingPrevious(parsed)
        LogManager.send("AI final cleanup complete", category: .ai, meetingID: meetingID)
        return result
    }

    // MARK: - Action-item ownership

    /// Persist every assigned commitment (dossiers export per person). The
    /// Meeting Intelligence pane still uses `keepsActionItem` so the on-screen
    /// list stays the user's own work plus unowned items (and the 1:1 exception).

    /// The roster used for filtering. When no attendee roster is available
    /// (no calendar link), fall back to the distinct non-"Me" speakers in the
    /// transcript so the 1:1 exception still works from diarization alone.
    nonisolated static func rosterForFiltering(_ roster: MeetingRoster?, segments: [SegmentSnapshot]) -> MeetingRoster {
        if let roster, !roster.otherAttendees.isEmpty { return roster }
        let others = Set(segments.filter { !$0.speaker.isMe }.map(\.speaker.displayName))
        let transcriptMeNames = segments
            .filter { $0.speaker.isMe && $0.speaker.displayName != Speaker.defaultMeLabel }
            .map(\.speaker.displayName)
        let myName = roster?.myName ?? transcriptMeNames.first
        let aliases = Array(Set((roster?.myAliases ?? []) + transcriptMeNames))
        return MeetingRoster(myName: myName, otherAttendees: Array(others), myAliases: aliases)
    }

    /// Whether an action item survives the ownership filter. Unowned items and
    /// the user's own items always stay; diarization placeholders count as
    /// unclear ownership (they could be anyone); anything clearly owned by
    /// another person stays only in a 1:1.
    nonisolated static func keepsActionItem(assignee: String?, roster: MeetingRoster) -> Bool {
        guard let raw = assignee?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return true }
        if raw == "me" || raw == "null" || raw == "unknown" { return true }
        if raw.hasPrefix("speaker ") { return true }
        let myLabels = ([roster.myName] + roster.myAliases)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if myLabels.contains(where: { $0 == raw || $0.contains(raw) || raw.contains($0) }) {
            return true
        }
        return roster.isOneOnOne
    }

    // MARK: - Private

    private func parseResponse(_ response: String, raw: String) throws -> AnalysisResult {
        let json: [String: Any]
        do {
            json = try AIResponseDecoder.objectFrom(response)
        } catch {
            LogManager.send(
                "AI parse failed (\(error.localizedDescription)) — raw response: "
                    + AIResponseDecoder.failureExcerpt(response),
                category: .ai,
                level: .error,
                meetingID: meetingID
            )
            throw error
        }

        let title = json["title"] as? String

        // summary is now a JSON array of section objects; re-encode to string for storage.
        // Fall back to plain string for any model that returns the old format.
        let summary: String
        if let sectionsArray = json["summary"] as? [[String: Any]],
           let reEncoded = try? JSONSerialization.data(withJSONObject: sectionsArray),
           let jsonString = String(data: reEncoded, encoding: .utf8) {
            summary = jsonString
        } else {
            summary = json["summary"] as? String ?? ""
        }

        var actionItems: [ParsedActionItem] = []
        if let items = json["action_items"] as? [[String: Any]] {
            for item in items {
                if let text = item["text"] as? String {
                    let assignee = item["assignee"] as? String
                    let sourceQuote = item["source_quote"] as? String
                    actionItems.append(ParsedActionItem(text: text, assignee: assignee, sourceQuote: sourceQuote))
                }
            }
        }

        let followUps = json["follow_ups"] as? [String] ?? []
        let topics = json["topics"] as? [String] ?? []

        return AnalysisResult(
            title: title,
            summary: summary,
            actionItems: actionItems,
            followUps: followUps,
            topics: topics,
            rawResponse: raw
        )
    }
}

enum AIParseError: LocalizedError {
    case invalidJSON(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let reason):
            "AI response was not valid JSON (\(reason))"
        }
    }
}

enum AITimeoutError: LocalizedError {
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            "AI request timed out after \(seconds) seconds"
        }
    }
}

/// Runs the given async throwing closure with a timeout. Throws `AITimeoutError.timedOut` if exceeded.
func withTimeout<T: Sendable>(seconds: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw AITimeoutError.timedOut(seconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
