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

// MARK: - Structured Summary Types

struct SummaryPoint: Sendable, Codable {
    let label: String
    let detail: String
}

struct SummarySection: Sendable, Codable {
    let title: String
    let intro: String?
    let points: [SummaryPoint]
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

    private var effectiveSystemPrompt: String {
        AIPromptTemplates.systemPromptWithContext(prep: prepContext)
    }

    func analyze(segments: [SegmentSnapshot]) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard nonEmpty.count > lastAnalyzedSegmentCount else {
            return nil
        }

        let newSegments = Array(nonEmpty.dropFirst(lastAnalyzedSegmentCount))
        guard !newSegments.isEmpty else { return nil }

        let transcript: String
        let userPrompt: String

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

        LogManager.send("AI analysis starting (\(nonEmpty.count) segments)", category: .ai, meetingID: meetingID)
        let capturedMeetingID = meetingID
        let response = try await AIRetry.run(label: "analyze", meetingID: capturedMeetingID) { [client, effectiveSystemPrompt, userPrompt] in
            try await withTimeout(seconds: 90) {
                try await client.sendMessage(
                    system: effectiveSystemPrompt,
                    userContent: userPrompt
                )
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

    func performFinalAnalysis(segments: [SegmentSnapshot]) async throws -> AnalysisResult? {
        let nonEmpty = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        // Single final pass with the full transcript. If we have prior accumulated context,
        // use the cleanup prompt; otherwise fall back to initial analysis.
        guard !previousSummary.isEmpty else {
            return try await analyze(segments: segments)
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
        let userPrompt = AIPromptTemplates.finalCleanupPrompt(
            fullTranscript: fullTranscript,
            currentSummary: previousSummary,
            currentActionItems: previousActionItems,
            currentFollowUps: previousFollowUps,
            currentTopics: previousTopics,
            suppressedActionItems: suppressedActionItems,
            suppressedFollowUps: suppressedFollowUps,
            relatedContext: relatedContext
        )

        LogManager.send("AI final cleanup starting (\(nonEmpty.count) segments)", category: .ai, meetingID: meetingID)
        let capturedMeetingID = meetingID
        let response = try await AIRetry.run(label: "finalCleanup", meetingID: capturedMeetingID) { [client, effectiveSystemPrompt, userPrompt] in
            try await withTimeout(seconds: 90) {
                try await client.sendMessage(
                    system: effectiveSystemPrompt,
                    userContent: userPrompt
                )
            }
        }
        LogManager.send("AI final cleanup raw response (\(response.count) chars): \(response.prefix(500))", category: .ai, meetingID: meetingID)

        let parsed = try parseResponse(response, raw: response)
        let result = applyResultPreservingPrevious(parsed)
        LogManager.send("AI final cleanup complete", category: .ai, meetingID: meetingID)
        return result
    }

    // MARK: - Private

    private func parseResponse(_ response: String, raw: String) throws -> AnalysisResult {
        let json: [String: Any]
        do {
            json = try AIResponseDecoder.objectFrom(response)
        } catch {
            LogManager.send("AI parse failed (\(error.localizedDescription)) — raw response: \(response.prefix(1000))", category: .ai, level: .error, meetingID: meetingID)
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
