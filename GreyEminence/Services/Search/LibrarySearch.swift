import Foundation

enum LibrarySearchScope: String, CaseIterable, Identifiable {
    case thisMeeting
    case selectedMeetings
    case allMeetings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMeeting: "This meeting"
        case .selectedMeetings: "Selected meetings"
        case .allMeetings: "All meetings"
        }
    }
}

struct LibrarySearchSources: OptionSet, Hashable {
    let rawValue: Int
    static let transcript = Self(rawValue: 1 << 0)
    static let intelligence = Self(rawValue: 1 << 1)
    static let both: Self = [.transcript, .intelligence]
}

struct LibrarySearchFilter: Equatable {
    var text: String = ""
    var useRegex: Bool = false
    var meetingName: String = ""
    var speaker: String = ""
    var fromDate: Date?
    var toDate: Date?
    var sources: LibrarySearchSources = .both

    var hasCriteria: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || fromDate != nil
            || toDate != nil
    }
}

struct LibrarySearchHit: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case transcript
        case summary
        case action
        case question
        case topic

        var label: String {
            switch self {
            case .transcript: "Transcript"
            case .summary: "Summary"
            case .action: "Action"
            case .question: "Question"
            case .topic: "Topic"
            }
        }
    }

    var id: String
    var meetingID: UUID
    var meetingTitle: String
    var meetingDate: Date
    var kind: Kind
    var snippet: String
    var speakerName: String?
    var segmentID: UUID?
}

enum LibrarySearch {
    static let defaultLimit = 200

    enum Outcome: Equatable {
        case hits([LibrarySearchHit])
        case invalidRegex(String)
    }

    static func matchesLiteral(_ haystack: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return haystack.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    static func compileRegex(_ pattern: String) -> NSRegularExpression? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
    }

    static func regexErrorMessage(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Regular expression is empty." }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func matchesRegex(_ haystack: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    static func speakerMatches(_ speaker: Speaker, filter: String) -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if needle.compare("me", options: .caseInsensitive) == .orderedSame
            || needle.compare("you", options: .caseInsensitive) == .orderedSame {
            return speaker.isMe
        }
        if speaker.isMe, let meName = SpeakerNames.effectiveMeName, matchesLiteral(meName, query: needle) {
            return true
        }
        return matchesLiteral(speaker.displayName, query: needle)
    }

    static func meetingNameMatches(_ meeting: Meeting, filter: String) -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if matchesLiteral(meeting.title, query: needle) { return true }
        if let generated = meeting.generatedTitle, matchesLiteral(generated, query: needle) { return true }
        if let series = meeting.seriesTitle, matchesLiteral(series, query: needle) { return true }
        return false
    }

    static func dateMatches(_ date: Date, from: Date?, to: Date?, calendar: Calendar = .current) -> Bool {
        if let from {
            if date < calendar.startOfDay(for: from) { return false }
        }
        if let to {
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
            if date >= next { return false }
        }
        return true
    }

    static func snippet(_ text: String, query: String, regex: NSRegularExpression?, radius: Int = 72) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        let matchRange: Range<String.Index>?
        if let regex {
            let ns = NSRange(compact.startIndex..<compact.endIndex, in: compact)
            if let found = regex.firstMatch(in: compact, options: [], range: ns),
               let range = Range(found.range, in: compact) {
                matchRange = range
            } else {
                matchRange = nil
            }
        } else {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            matchRange = needle.isEmpty
                ? nil
                : compact.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        }
        guard let range = matchRange else {
            return String(compact.prefix(radius * 2))
        }
        let start = compact.index(range.lowerBound, offsetBy: -radius, limitedBy: compact.startIndex)
            ?? compact.startIndex
        let end = compact.index(range.upperBound, offsetBy: radius, limitedBy: compact.endIndex)
            ?? compact.endIndex
        var piece = String(compact[start..<end])
        if start > compact.startIndex { piece = "…" + piece }
        if end < compact.endIndex { piece += "…" }
        return piece
    }

    static func search(
        filter: LibrarySearchFilter,
        in meetings: [Meeting],
        limit: Int = defaultLimit
    ) -> Outcome {
        guard filter.hasCriteria else { return .hits([]) }

        let textNeedle = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if filter.useRegex, !textNeedle.isEmpty, let message = regexErrorMessage(textNeedle) {
            return .invalidRegex(message)
        }

        let regex: NSRegularExpression?
        if filter.useRegex, !textNeedle.isEmpty {
            regex = compileRegex(textNeedle)
        } else {
            regex = nil
        }

        let textMatches: (String) -> Bool = { haystack in
            if textNeedle.isEmpty { return true }
            if let regex {
                return matchesRegex(haystack, regex: regex)
            }
            return matchesLiteral(haystack, query: textNeedle)
        }

        var hits: [LibrarySearchHit] = []
        let ordered = meetings.sorted { $0.date > $1.date }
        meetingLoop: for meeting in ordered {
            guard meetingNameMatches(meeting, filter: filter.meetingName) else { continue }
            guard dateMatches(meeting.date, from: filter.fromDate, to: filter.toDate) else { continue }

            if filter.sources.contains(.transcript) {
                let segments = meeting.segments.sorted { $0.startTime < $1.startTime }
                for segment in segments {
                    guard speakerMatches(segment.speaker, filter: filter.speaker) else { continue }
                    guard textMatches(segment.text) else { continue }
                    hits.append(
                        LibrarySearchHit(
                            id: "t-\(segment.id.uuidString)",
                            meetingID: meeting.id,
                            meetingTitle: meeting.title,
                            meetingDate: meeting.date,
                            kind: .transcript,
                            snippet: snippet(segment.text, query: textNeedle, regex: regex),
                            speakerName: segment.speaker.displayName,
                            segmentID: segment.id
                        )
                    )
                    if hits.count >= limit { break meetingLoop }
                }
            }

            if filter.sources.contains(.intelligence) {
                let speakerFilter = filter.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
                if speakerFilter.isEmpty {
                    if textMatches(meeting.title) {
                        hits.append(
                            LibrarySearchHit(
                                id: "title-\(meeting.id.uuidString)",
                                meetingID: meeting.id,
                                meetingTitle: meeting.title,
                                meetingDate: meeting.date,
                                kind: .summary,
                                snippet: meeting.title,
                                speakerName: nil,
                                segmentID: nil
                            )
                        )
                        if hits.count >= limit { break meetingLoop }
                    }

                    if let insight = meeting.insights.max(by: { $0.createdAt < $1.createdAt }) {
                        if textMatches(insight.summary) {
                            hits.append(
                                LibrarySearchHit(
                                    id: "sum-\(insight.id.uuidString)",
                                    meetingID: meeting.id,
                                    meetingTitle: meeting.title,
                                    meetingDate: meeting.date,
                                    kind: .summary,
                                    snippet: snippet(insight.summary, query: textNeedle, regex: regex),
                                    speakerName: nil,
                                    segmentID: nil
                                )
                            )
                            if hits.count >= limit { break meetingLoop }
                        }
                        for (index, question) in insight.followUpQuestions.enumerated() where textMatches(question) {
                            hits.append(
                                LibrarySearchHit(
                                    id: "q-\(insight.id.uuidString)-\(index)",
                                    meetingID: meeting.id,
                                    meetingTitle: meeting.title,
                                    meetingDate: meeting.date,
                                    kind: .question,
                                    snippet: snippet(question, query: textNeedle, regex: regex),
                                    speakerName: nil,
                                    segmentID: nil
                                )
                            )
                            if hits.count >= limit { break meetingLoop }
                        }
                        for (index, topic) in insight.topics.enumerated() where textMatches(topic) {
                            hits.append(
                                LibrarySearchHit(
                                    id: "top-\(insight.id.uuidString)-\(index)",
                                    meetingID: meeting.id,
                                    meetingTitle: meeting.title,
                                    meetingDate: meeting.date,
                                    kind: .topic,
                                    snippet: topic,
                                    speakerName: nil,
                                    segmentID: nil
                                )
                            )
                            if hits.count >= limit { break meetingLoop }
                        }
                    }
                }

                for item in meeting.actionItems {
                    if !speakerFilter.isEmpty {
                        let assignee = item.assignee ?? ""
                        let meName = SpeakerNames.effectiveMeName ?? "Me"
                        let isMeFilter = speakerFilter.compare("me", options: .caseInsensitive) == .orderedSame
                            || speakerFilter.compare("you", options: .caseInsensitive) == .orderedSame
                        let ok = isMeFilter
                            ? matchesLiteral(assignee, query: meName) || matchesLiteral(assignee, query: "Me")
                            : matchesLiteral(assignee, query: speakerFilter)
                        guard ok else { continue }
                    }
                    guard textMatches(item.text) else { continue }
                    hits.append(
                        LibrarySearchHit(
                            id: "a-\(item.id.uuidString)",
                            meetingID: meeting.id,
                            meetingTitle: meeting.title,
                            meetingDate: meeting.date,
                            kind: .action,
                            snippet: snippet(item.text, query: textNeedle, regex: regex),
                            speakerName: item.assignee,
                            segmentID: item.sourceSegmentID
                        )
                    )
                    if hits.count >= limit { break meetingLoop }
                }
            }
        }
        return .hits(hits)
    }

    /// Compatibility wrapper used by older tests.
    static func search(
        query: String,
        in meetings: [Meeting],
        sources: LibrarySearchSources,
        limit: Int = defaultLimit
    ) -> [LibrarySearchHit] {
        var filter = LibrarySearchFilter()
        filter.text = query
        filter.sources = sources
        if case .hits(let hits) = search(filter: filter, in: meetings, limit: limit) {
            return hits
        }
        return []
    }
}
