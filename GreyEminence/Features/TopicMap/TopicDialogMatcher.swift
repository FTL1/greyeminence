import Foundation

struct TopicDialogSnippet: Identifiable, Equatable {
    let id: UUID
    let meetingID: UUID
    let meetingTitle: String
    let meetingDate: Date
    let speakerName: String
    let timestamp: String
    let startTime: TimeInterval
    let text: String
    let isCurrentMeeting: Bool
}

enum TopicDialogMatcher {
    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "to", "in", "on", "for",
        "with", "at", "by", "from", "as", "is", "are"
    ]

    static func normalize(_ topic: String) -> String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func topicsMatch(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    static func significantTokens(in topic: String) -> [String] {
        let parts = normalize(topic)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        return parts.isEmpty
            ? normalize(topic).split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
            : parts
    }

    /// Whether a transcript line is about this topic. Phrase match, or every
    /// significant token present (single-token topics use a word-boundary).
    static func segmentMatches(_ text: String, topic: String) -> Bool {
        let haystack = text.lowercased()
        let phrase = normalize(topic)
        guard !phrase.isEmpty else { return false }
        if haystack.contains(phrase) { return true }

        let tokens = significantTokens(in: topic)
        guard !tokens.isEmpty else { return false }
        if tokens.count == 1 {
            return containsWord(tokens[0], in: haystack)
        }
        return tokens.allSatisfy { containsWord($0, in: haystack) }
    }

    static func snippets(
        from segments: [TranscriptSegment],
        topic: String,
        meeting: Meeting,
        isCurrentMeeting: Bool,
        limit: Int = 16
    ) -> [TopicDialogSnippet] {
        let ordered = segments.sorted { $0.startTime < $1.startTime }
        var hits: [TopicDialogSnippet] = []
        var seen = Set<UUID>()
        for segment in ordered {
            guard hits.count < limit else { break }
            guard segmentMatches(segment.text, topic: topic) else { continue }
            guard seen.insert(segment.id).inserted else { continue }
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            hits.append(
                TopicDialogSnippet(
                    id: segment.id,
                    meetingID: meeting.id,
                    meetingTitle: meeting.title,
                    meetingDate: meeting.date,
                    speakerName: segment.speaker.displayName,
                    timestamp: segment.formattedTimestamp,
                    startTime: segment.startTime,
                    text: text,
                    isCurrentMeeting: isCurrentMeeting
                )
            )
        }
        return hits
    }

    static func meetings(
        sharing topic: String,
        excluding meetingID: UUID,
        among meetings: [Meeting]
    ) -> [Meeting] {
        meetings
            .filter { meeting in
                meeting.id != meetingID
                    && (meeting.latestInsight?.topics.contains { topicsMatch($0, topic) } ?? false)
            }
            .sorted { $0.date > $1.date }
    }

    private static func containsWord(_ word: String, in haystack: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.caseInsensitive]
        ) else {
            return haystack.contains(word)
        }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        return regex.firstMatch(in: haystack, range: range) != nil
    }
}
