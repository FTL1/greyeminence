import Foundation
import SwiftData

struct MeetingPrepContext: Sendable {
    /// Human-readable provenance, e.g. "From your last 2 OLP Team Sync meetings".
    /// Empty when there's no prior history to draw on.
    let sourceSummary: String
    let unresolvedItems: [PrepActionItem]
    let previousTopics: [String]
    let followUps: [String]
    let attendeeNames: [String]

    var isEmpty: Bool {
        unresolvedItems.isEmpty && previousTopics.isEmpty && followUps.isEmpty
    }
}

struct PrepActionItem: Sendable, Identifiable {
    let id: UUID
    let text: String
    let assignee: String?
    let meetingTitle: String
    let meetingDate: Date
    let daysSinceCreated: Int
}

@MainActor
final class MeetingPrepService {
    /// How many recent prior meetings to base prep on. Keeps the card grounded
    /// in the last couple of conversations instead of every meeting in history,
    /// so a months-old stray item can't dominate the list.
    static let recentMeetingLimit = 2

    /// Gather prep context for the meeting the user is about to record, drawn
    /// from the most recent occurrences of its series (or, failing that, the
    /// most recent meetings sharing its attendees).
    func gatherPrepContext(
        for event: CalendarEvent,
        attendees: [Contact],
        seriesID: UUID?,
        in context: ModelContext
    ) -> MeetingPrepContext {
        // Candidate prior meetings: the recurring series (if any) ∪ any meeting
        // these attendees were in. Series presence drives the summary wording.
        var related: Set<UUID> = []
        var isSeries = false
        if let seriesID {
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate<Meeting> { $0.seriesID == seriesID }
            )
            if let seriesMeetings = try? context.fetch(descriptor), !seriesMeetings.isEmpty {
                isSeries = true
                for m in seriesMeetings { related.insert(m.id) }
            }
        }
        for contact in attendees {
            for meeting in contact.meetings { related.insert(meeting.id) }
        }

        // Keep only the most recent N related meetings (newest first), so the
        // prep reflects the last couple of conversations rather than the whole
        // history.
        let allMeetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        let relatedMeetings = allMeetings.filter { related.contains($0.id) }
        let recentIDs = Self.recentMeetingIDs(
            from: relatedMeetings.map { (id: $0.id, date: $0.date) },
            limit: Self.recentMeetingLimit
        )
        let recent = recentIDs.compactMap { id in relatedMeetings.first { $0.id == id } }

        var unresolvedItems: [PrepActionItem] = []
        var previousTopics: [String] = []
        var followUps: [String] = []
        let now = Date.now
        for meeting in recent {
            for item in meeting.actionItems where !item.isCompleted {
                let days = Calendar.current.dateComponents([.day], from: item.createdAt, to: now).day ?? 0
                unresolvedItems.append(PrepActionItem(
                    id: item.id,
                    text: item.text,
                    assignee: item.displayAssignee,
                    meetingTitle: meeting.title,
                    meetingDate: meeting.date,
                    daysSinceCreated: days
                ))
            }
            for insight in meeting.insights {
                previousTopics.append(contentsOf: insight.topics)
                followUps.append(contentsOf: insight.followUpQuestions)
            }
        }

        return MeetingPrepContext(
            sourceSummary: Self.summary(
                count: recent.count,
                isSeries: isSeries,
                seriesTitle: event.title,
                attendeeNames: attendees.map(\.name)
            ),
            // Newest meeting first — the most recent conversation is the most
            // relevant context, not the oldest unresolved item.
            unresolvedItems: unresolvedItems.sorted { $0.meetingDate > $1.meetingDate },
            previousTopics: Self.dedupePreservingOrder(previousTopics),
            followUps: Self.dedupePreservingOrder(followUps),
            attendeeNames: attendees.map(\.name)
        )
    }

    // MARK: - Pure helpers (unit-tested without SwiftData)

    /// The most recent `limit` meeting ids (newest first) from a related set.
    nonisolated static func recentMeetingIDs(from meetings: [(id: UUID, date: Date)], limit: Int) -> [UUID] {
        meetings.sorted { $0.date > $1.date }.prefix(limit).map(\.id)
    }

    /// Provenance line for the prep card. Series wording when the meeting is
    /// recurring; otherwise names the people. Empty when there's no history.
    nonisolated static func summary(count: Int, isSeries: Bool, seriesTitle: String?, attendeeNames: [String]) -> String {
        if count == 0 { return "" }
        if isSeries, let title = seriesTitle, !title.isEmpty {
            return count == 1
                ? "From your last \(title)"
                : "From your last \(count) \(title) meetings"
        }
        let names = attendeeNames.prefix(2).joined(separator: ", ")
        if names.isEmpty {
            return count == 1 ? "From your last meeting" : "From your last \(count) meetings"
        }
        return count == 1
            ? "From your last meeting with \(names)"
            : "From your last \(count) meetings with \(names)"
    }

    /// Deduplicate keeping first-seen order (stable, unlike `Set`).
    nonisolated static func dedupePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items where seen.insert(item).inserted { out.append(item) }
        return out
    }
}
