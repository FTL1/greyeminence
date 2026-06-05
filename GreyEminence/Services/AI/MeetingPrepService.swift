import Foundation
import SwiftData

struct MeetingPrepContext: Sendable {
    /// Why this card exists — drives both the UI and whether we have real
    /// history to feed the AI prompt.
    enum Provenance: Sendable, Equatable {
        /// Prior recorded occurrences of this exact meeting were found.
        case history(summary: String)
        /// A recurring meeting we've never recorded before — no history yet.
        case firstOccurrence(title: String)
        /// A one-off meeting: there is no "previous occurrence" to prep from.
        case notApplicable
    }

    let provenance: Provenance
    let unresolvedItems: [PrepActionItem]
    let previousTopics: [String]
    let followUps: [String]

    var hasContent: Bool {
        !unresolvedItems.isEmpty || !previousTopics.isEmpty || !followUps.isEmpty
    }

    /// Whether the card should appear at all. One-offs show nothing; recurring
    /// meetings always show *something* (real prep, or a stated "no history yet").
    var shouldDisplay: Bool {
        switch provenance {
        case .notApplicable: return false
        case .firstOccurrence, .history: return true
        }
    }

    /// Gate for injecting context into the AI prompt: only when there is actual
    /// carried-over content from prior occurrences.
    var isEmpty: Bool { !hasContent }
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
    /// How many recent prior occurrences to base prep on — the user cares mainly
    /// about the previous meeting, with one more for continuity.
    static let recentMeetingLimit = 2

    /// Gather prep context for the meeting the user is about to record, drawn
    /// **only** from prior recorded occurrences of this same recurring meeting.
    ///
    /// Deliberately NOT attendee-based: sharing attendees with unrelated meetings
    /// is not a meeting relationship, and pulling their action items/topics in
    /// produces nonsense (e.g. a "Client Data" meeting showing "US Politics"
    /// topics from an unrelated chat with the same two people). When there's no
    /// recorded history of *this* meeting, we say so rather than inventing prep.
    func gatherPrepContext(for event: CalendarEvent, in context: ModelContext) -> MeetingPrepContext {
        func empty(_ provenance: MeetingPrepContext.Provenance) -> MeetingPrepContext {
            MeetingPrepContext(provenance: provenance, unresolvedItems: [], previousTopics: [], followUps: [])
        }

        // Prep is anchored to the recurring series. A one-off has no prior
        // occurrence to prep from.
        guard let recurrenceID = event.recurrenceID else {
            return empty(.notApplicable)
        }

        // Prior recorded occurrences: meetings linked to the same recurrence key.
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == recurrenceID }
        )
        let priorOccurrences = ((try? context.fetch(descriptor)) ?? [])
            .sorted { $0.date > $1.date }

        guard !priorOccurrences.isEmpty else {
            return empty(.firstOccurrence(title: event.title ?? "this meeting"))
        }

        let recent = Array(priorOccurrences.prefix(Self.recentMeetingLimit))

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
                    assignee: Self.cleanAssignee(item.displayAssignee),
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
            provenance: .history(summary: Self.historySummary(count: recent.count, mostRecent: recent.first?.date)),
            // Newest occurrence first — the previous meeting is the priority.
            unresolvedItems: unresolvedItems.sorted { $0.meetingDate > $1.meetingDate },
            previousTopics: Self.dedupePreservingOrder(previousTopics),
            followUps: Self.dedupePreservingOrder(followUps)
        )
    }

    // MARK: - Pure helpers (unit-tested without SwiftData)

    /// Provenance line for the prep card when prior occurrences exist.
    nonisolated static func historySummary(count: Int, mostRecent: Date?) -> String {
        if count <= 1 {
            if let mostRecent {
                return "From the last time you recorded this meeting · \(shortDate(mostRecent))"
            }
            return "From the last time you recorded this meeting"
        }
        return "From your last \(count) recordings of this meeting"
    }

    nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Suppress diarization placeholders ("Speaker 2", "Unknown", "Me") that
    /// aren't real owners — showing them as an assignee is noise.
    nonisolated static func cleanAssignee(_ assignee: String?) -> String? {
        guard let trimmed = assignee?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "me" || lower == "unknown" || lower.hasPrefix("speaker ") { return nil }
        return trimmed
    }

    /// Deduplicate keeping first-seen order (stable, unlike `Set`).
    nonisolated static func dedupePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items where seen.insert(item).inserted { out.append(item) }
        return out
    }
}
