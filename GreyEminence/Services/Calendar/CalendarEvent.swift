import Foundation

/// Provider-neutral event attendee: a person on the invite, with whatever
/// identity the calendar source supplied. Carries the email so linking a
/// meeting can create real Contact records for people we haven't met yet.
struct EventAttendee: Sendable, Hashable {
    let name: String
    /// Normalized (lowercased) address, or nil when the provider had none.
    let email: String?
    /// True when the provider identified this attendee as the signed-in user
    /// (EventKit only — Graph can't tell). Guards against creating a duplicate
    /// contact for the user themself.
    let isCurrentUser: Bool

    init(name: String, email: String? = nil, isCurrentUser: Bool = false) {
        self.name = name
        self.email = email
        self.isCurrentUser = isCurrentUser
    }

    /// Best name/email pair from whatever the provider supplied. Providers
    /// sometimes put the address in the display-name slot — detect that and
    /// derive a readable name from the local part. nil when there's neither
    /// a usable name nor an address.
    static func resolve(name rawName: String?, email rawEmail: String?, isCurrentUser: Bool = false) -> EventAttendee? {
        let email = normalize(rawEmail)
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.contains("@") {
            let asEmail = normalize(name)
            return EventAttendee(
                name: displayName(fromEmail: asEmail ?? name),
                email: email ?? asEmail,
                isCurrentUser: isCurrentUser
            )
        }
        if !name.isEmpty {
            return EventAttendee(name: name, email: email, isCurrentUser: isCurrentUser)
        }
        if let email {
            return EventAttendee(name: displayName(fromEmail: email), email: email, isCurrentUser: isCurrentUser)
        }
        return nil
    }

    /// "sam.lee@org.com" → "Sam Lee". Best-effort readable name for
    /// attendees the provider only identified by address.
    static func displayName(fromEmail email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let words = local.split(whereSeparator: { ".-_".contains($0) })
        guard !words.isEmpty else { return email }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func normalize(_ email: String?) -> String? {
        guard let value = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              value.contains("@") else { return nil }
        return value
    }
}

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
    /// Attendees (people only — rooms/resources are filtered at fetch time),
    /// already extracted from the provider's participant objects.
    let attendees: [EventAttendee]
    let isRecurring: Bool
    /// The organizer called it off. Cancelled events are filtered out before
    /// they reach the UI; the flag exists so the two calendar providers can
    /// report it the same way.
    var isCancelled: Bool = false
    let source: Source

    /// Recurrence/series key, or nil for a one-off event.
    var recurrenceID: String? { isRecurring ? linkIdentifier : nil }

    /// Exchange and Outlook commonly deliver a cancellation by *retitling* the
    /// event "Canceled: <subject>" rather than by setting a status the client
    /// can read — a cancelled meeting can still arrive as `.confirmed`.
    static func titleIndicatesCancellation(_ title: String?) -> Bool {
        guard let title = title?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return false
        }
        return title.hasPrefix("canceled:") || title.hasPrefix("cancelled:")
    }

    /// Start time formatted for display (e.g. "10:30 AM"). One definition for
    /// every calendar-event row instead of re-formatting at each call site.
    var displayTime: String {
        startDate.formatted(date: .omitted, time: .shortened)
    }
}
