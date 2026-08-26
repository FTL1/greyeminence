import Foundation

/// Conversation persistence: one JSON file in Application Support.
///
/// A file rather than SwiftData because conversations are derived, disposable
/// data — losing them costs a re-ask, not a meeting — and giving them a
/// `@Model` would mean a schema version bump plus a migration for every future
/// change to the shape. A file rather than `UserDefaults` (where the old
/// one-shot Ask history lived) because a thread with a hundred snippets is
/// far past the size that belongs in a preferences plist.
enum AskConversationStore {
    /// Threads beyond this are pruned oldest-first on save.
    static let maxConversations = 60

    private static var fileURL: URL {
        StorageManager.shared.appSupportURL.appendingPathComponent("AskConversations.json")
    }

    static func load() -> [AskConversation] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return migrateLegacyHistory()
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AskConversation].self, from: data)
        } catch {
            LogManager.send(
                "Ask: couldn't read conversations — starting empty: \(error.localizedDescription)",
                category: .general,
                level: .warning
            )
            return []
        }
    }

    static func save(_ conversations: [AskConversation]) {
        let trimmed = Array(
            conversations
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(maxConversations)
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(trimmed)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            LogManager.send(
                "Ask: couldn't save conversations: \(error.localizedDescription)",
                category: .general,
                level: .warning
            )
        }
    }

    // MARK: - Legacy history

    private static let legacyKey = "askHistory"

    /// The previous Ask stored a flat list of one-shot searches in
    /// `UserDefaults`. Each becomes a single-turn conversation so the work
    /// already done stays reachable, then the old key is cleared so this
    /// runs exactly once.
    private static func migrateLegacyHistory() -> [AskConversation] {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else { return [] }
        defer { UserDefaults.standard.removeObject(forKey: legacyKey) }

        guard let entries = try? JSONDecoder().decode([LegacyEntry].self, from: data),
              !entries.isEmpty else { return [] }

        let converted: [AskConversation] = entries.map { entry in
            var turn = AskTurn(question: entry.query, createdAt: entry.timestamp)
            turn.answer = entry.synthesizedAnswer
            let numbers = Array(1...max(entry.results.count, 1)).prefix(entry.results.count)
            turn.retrievedNumbers = Array(numbers)
            turn.promptedNumbers = Array(numbers)
            turn.citedNumbers = entry.synthesizedAnswer.map { AskCitations.cited(in: $0) } ?? []

            let sources = entry.results.enumerated().map { index, result in
                AskSource(number: index + 1, result: result, firstSeenTurn: turn.id)
            }
            return AskConversation(
                title: AskConversation.title(fromFirstQuestion: entry.query),
                createdAt: entry.timestamp,
                updatedAt: entry.timestamp,
                dateFilterRaw: entry.dateFilterRaw ?? AskDateFilter.anyTime.rawValue,
                turns: [turn],
                sources: sources
            )
        }

        LogManager.send("Ask: migrated \(converted.count) saved search(es) into conversations", category: .general)
        save(converted)
        return converted
    }

    private struct LegacyEntry: Codable {
        var id: UUID
        var query: String
        var timestamp: Date
        var results: [CodableSearchResult]
        var synthesizedAnswer: String?
        var dateFilterRaw: String?
    }
}
