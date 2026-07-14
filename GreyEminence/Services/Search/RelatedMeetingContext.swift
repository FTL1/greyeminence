import Foundation

/// Retrieves transcript snippets from OTHER meetings that are semantically
/// related to the current meeting's topics. The final analysis pass injects
/// them so follow-up questions can surface blind spots — things relevant to
/// this meeting's purpose that nobody brought up, including context that was
/// discussed elsewhere but ignored here.
enum RelatedMeetingContext {

    /// Total snippets in the block — enough to surface adjacent context
    /// without bloating the prompt.
    static let snippetLimit = 10
    /// Per-meeting cap so one closely-related meeting doesn't monopolize
    /// the block; diversity across meetings is what exposes blind spots.
    static let perMeetingCap = 3
    /// Topics folded into the search query. Topic lists are ordered by
    /// prominence, so the head carries the meeting's identity.
    static let queryTopicLimit = 8

    /// Provider closure for `AIIntelligenceService` — called with the
    /// meeting's accumulated topics at final-analysis time.
    static func provider(excludingMeetingID meetingID: UUID?) -> @Sendable ([String]) async -> String? {
        { topics in
            await build(topics: topics, excludingMeetingID: meetingID)
        }
    }

    /// Search the embedding store (transcript segments only — the same
    /// restriction Ask uses) and format the results. Returns nil when the
    /// store is unavailable, the provider isn't ready, or nothing matches.
    @MainActor
    static func build(topics: [String], excludingMeetingID meetingID: UUID?) async -> String? {
        let query = topics.prefix(queryTopicLimit).joined(separator: ", ")
        guard !query.isEmpty, let store = EmbeddingStore.shared else { return nil }

        let providerRaw = UserDefaults.standard.string(forKey: "embeddingProvider") ?? EmbeddingProvider.nlEmbedding.rawValue
        let provider = EmbeddingProvider(rawValue: providerRaw) ?? .nlEmbedding
        let service = provider.makeService()
        guard service.isAvailable else { return nil }

        let search = SemanticSearchService(store: store, service: service)
        let found = await search.search(query, topK: 40, kinds: [.transcriptSegment])
        return format(results: found.filter { $0.meetingID != meetingID })
    }

    /// Diversity-capped snippet list, one line per result. Pure — unit-tested
    /// without the embedding store.
    static func format(results: [SearchResult]) -> String? {
        var perMeeting: [UUID: Int] = [:]
        var lines: [String] = []
        for result in results {
            guard lines.count < snippetLimit else { break }
            let used = perMeeting[result.meetingID, default: 0]
            guard used < perMeetingCap else { continue }
            let snippet = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty else { continue }
            perMeeting[result.meetingID] = used + 1
            let date = result.meetingDate.formatted(date: .abbreviated, time: .omitted)
            lines.append("- [\(result.meetingTitle) — \(date)] \(snippet.prefix(300))")
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}
