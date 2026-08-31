import Foundation

/// Grounded snapshot of one meeting. Every string is copied from storage
/// or the transcript — nothing is paraphrased here.
struct DossierMeetingSnapshot: Sendable, Equatable {
    var id: UUID
    var title: String
    var generatedTitle: String?
    var date: Date
    var durationLabel: String
    var durationMinutes: Int
    var attendees: [String]
    var speakers: [String]
    var myLabels: [String]
    var summaryJSON: String
    var actionItems: [DossierAction]
    var followUps: [String]
    var topics: [String]
    var shareNarratives: [DossierShare]
    var transcript: [DossierLine]
}

struct DossierAction: Sendable, Equatable {
    var text: String
    var assignee: String?
    var isCompleted: Bool
    var sourceQuote: String?
}

struct DossierShare: Sendable, Equatable {
    var title: String
    var span: String
    var narrative: String
}

struct DossierLine: Sendable, Equatable {
    var speaker: String
    var timestamp: String
    var text: String
    var isMe: Bool
}

enum DossierFacts {
    @MainActor
    static func snapshot(meeting: Meeting) -> DossierMeetingSnapshot {
        let roster = MeetingRoster.snapshot(for: meeting)
        let myLabels = ([roster.myName] + roster.myAliases).compactMap { $0 }
        let sorted = meeting.segments.sorted { $0.startTime < $1.startTime }
        var speakers: [String] = []
        for segment in sorted {
            let name = segment.speaker.displayName
            if !speakers.contains(where: { DossierNaming.namesMatch($0, name) }) {
                speakers.append(name)
            }
        }
        for attendee in meeting.attendees.map(\.name) where !speakers.contains(where: { DossierNaming.namesMatch($0, attendee) }) {
            speakers.append(attendee)
        }

        let insight = meeting.latestInsight
        return DossierMeetingSnapshot(
            id: meeting.id,
            title: meeting.title,
            generatedTitle: meeting.generatedTitle,
            date: meeting.date,
            durationLabel: meeting.formattedDuration,
            durationMinutes: ReportModelBuilder.durationMinutes(meeting.duration),
            attendees: meeting.attendees.map(\.name).sorted(),
            speakers: speakers,
            myLabels: myLabels,
            summaryJSON: insight?.summary ?? "",
            actionItems: meeting.actionItems.map {
                DossierAction(
                    text: $0.text,
                    assignee: $0.displayAssignee ?? $0.assignee,
                    isCompleted: $0.isCompleted,
                    sourceQuote: sourceQuote(for: $0, in: sorted)
                )
            },
            followUps: insight?.followUpQuestions ?? [],
            topics: insight?.topics ?? [],
            shareNarratives: meeting.sessionSummaries
                .sorted { $0.startTime < $1.startTime }
                .map {
                    DossierShare(
                        title: $0.windowTitle?.isEmpty == false ? $0.windowTitle! : "Shared screen",
                        span: "\(formatTime($0.startTime))–\(formatTime($0.endTime))",
                        narrative: $0.narrative
                    )
                },
            transcript: sorted.compactMap { segment in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DossierLine(
                    speaker: segment.speaker.displayName,
                    timestamp: segment.formattedTimestamp,
                    text: text,
                    isMe: segment.speaker.isMe
                )
            }
        )
    }

    /// Calendar series if linked, otherwise the related-name bucket
    /// (first two words, two or more meetings). Falls back to this meeting.
    @MainActor
    static func relatedMeetings(to meeting: Meeting, library: [Meeting]) -> [Meeting] {
        let pool = library.filter { !$0.isInterviewMeeting }
        if let seriesID = meeting.seriesID {
            let same = pool.filter { $0.seriesID == seriesID }.sorted { $0.date < $1.date }
            if same.count > 1 { return same }
        }
        let sections = MeetingListGrouping.namedSections(for: pool, related: true)
        if let group = sections.first(where: { pair in pair.1.contains { $0.id == meeting.id } }),
           group.1.count > 1 {
            return group.1.sorted { $0.date < $1.date }
        }
        return [meeting]
    }

    static func purpose(from snapshot: DossierMeetingSnapshot) -> String? {
        if let generated = snapshot.generatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !generated.isEmpty {
            return generated
        }
        if let sections = SummarySection.parse(snapshot.summaryJSON),
           let first = sections.first {
            if let intro = first.intro?.trimmingCharacters(in: .whitespacesAndNewlines), !intro.isEmpty {
                return intro
            }
            return first.title
        }
        return nil
    }

    static func filterActions(_ items: [DossierAction], audience: DossierAudience, myLabels: [String]) -> [DossierAction] {
        switch audience {
        case .boss, .general:
            return items
        case .me:
            return items.filter { item in
                guard let assignee = item.assignee, !assignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return true
                }
                return DossierNaming.isMeName(assignee, myLabels: myLabels)
            }
        case .person(let name):
            return items.filter { item in
                guard let assignee = item.assignee else { return false }
                return DossierNaming.namesMatch(assignee, name)
            }
        }
    }

    static func filterTranscript(_ lines: [DossierLine], audience: DossierAudience, myLabels _: [String]) -> [DossierLine] {
        switch audience {
        case .me, .boss, .general:
            return lines
        case .person(let name):
            return lines.filter { DossierNaming.namesMatch($0.speaker, name) }
        }
    }

    static func followUps(_ questions: [String], audience: DossierAudience) -> [String] {
        switch audience {
        case .person(let name):
            let hits = questions.filter { $0.localizedCaseInsensitiveContains(name) }
            return hits.isEmpty ? questions : hits
        case .me, .boss, .general:
            return questions
        }
    }

    static func capSummary(_ sections: [SummarySection], depth: DossierDepth) -> [SummarySection] {
        switch depth {
        case .brief:
            let first = Array(sections.prefix(2))
            return first.map { section in
                SummarySection(
                    title: section.title,
                    intro: section.intro,
                    points: Array(section.points.prefix(3))
                )
            }
        case .summary, .detailed:
            return sections
        }
    }

    static func capList<T>(_ items: [T], depth: DossierDepth) -> [T] {
        switch depth {
        case .brief: Array(items.prefix(5))
        case .summary, .detailed: items
        }
    }

    /// Verbatim lines only — longest first, capped. Never paraphrased.
    static func speakerQuotes(from lines: [DossierLine], limit: Int) -> [DossierLine] {
        Array(lines.sorted { $0.text.count > $1.text.count }.prefix(limit))
            .sorted { $0.timestamp < $1.timestamp }
    }

    @MainActor
    private static func sourceQuote(for item: ActionItem, in segments: [TranscriptSegment]) -> String? {
        guard let id = item.sourceSegmentID,
              let segment = segments.first(where: { $0.id == id }) else { return nil }
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func formatTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
