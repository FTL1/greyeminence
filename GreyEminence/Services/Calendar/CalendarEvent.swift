import Foundation

/// Provider-neutral calendar event. Lets the recording flow work the same way
/// whether an event came from the local EventKit store or Microsoft Graph.
struct CalendarEvent: Identifiable, Sendable, Hashable {
    enum Source: String, Sendable {
        case eventKit
        case microsoftGraph

        var label: String {
            switch self {
            case .eventKit: "On this Mac"
            case .microsoftGraph: "Microsoft 365"
            }
        }
    }

    /// Per-occurrence identity, unique among the events shown in a list. Used as
    /// the SwiftUI `ForEach`/selection id. (EventKit `eventIdentifier`; Graph
    /// instance `id`.) Recurring occurrences must NOT collide here.
    let id: String

    /// Identifier persisted to `Meeting.calendarEventID`. Shared across all
    /// occurrences of a recurring event so recurring-series matching keeps
    /// working. (EventKit `calendarItemIdentifier`; Graph `seriesMasterId ?? id`.)
    let linkIdentifier: String

    let title: String?
    let startDate: Date
    let endDate: Date
    /// Attendee display names (or emails), already extracted at fetch time.
    let attendees: [String]
    let isRecurring: Bool
    let source: Source

    /// Recurrence/series key, or nil for a one-off event.
    var recurrenceID: String? { isRecurring ? linkIdentifier : nil }

    /// Start time formatted for display (e.g. "10:30 AM"). One definition for
    /// every calendar-event row instead of re-formatting at each call site.
    var displayTime: String {
        startDate.formatted(date: .omitted, time: .shortened)
    }
}
