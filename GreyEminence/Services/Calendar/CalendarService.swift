import EventKit
import SwiftData

@Observable
@MainActor
final class CalendarService {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    private(set) var authorizationState: AuthorizationState = .notDetermined
    private(set) var currentEvent: EKEvent?

    private nonisolated(unsafe) let store = EKEventStore()

    init() {
        // Seed from the system's current authorization so MenuBar /
        // auto-detection startRecording paths (which don't go through the
        // RecordingView .task that calls requestAccess) don't silently fall
        // into "not authorized" when the user already granted access in a
        // prior session.
        authorizationState = Self.systemAuthorizationState()
    }

    private static func systemAuthorizationState() -> AuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: .authorized
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAccess() async {
        LogManager.shared.log("Calendar: requesting full access", category: .general)
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationState = granted ? .authorized : .denied
            LogManager.shared.log(
                "Calendar: access \(granted ? "granted" : "denied by user/system")",
                category: .general,
                level: granted ? .info : .warning
            )
        } catch {
            authorizationState = .denied
            // Most common cause of a thrown error here: missing
            // NSCalendarsFullAccessUsageDescription in Info.plist — the system
            // refuses to even prompt without it.
            LogManager.shared.log(
                "Calendar: access request failed — \(error.localizedDescription) (check NSCalendarsFullAccessUsageDescription in Info.plist)",
                category: .general,
                level: .warning
            )
        }
    }

    /// Find the current or upcoming calendar event within a time window.
    /// Defaults to ±60 min so a meeting already in progress (started up to an
    /// hour ago) or starting soon is still detected — the previous ±15 min
    /// window missed long meetings the user joined late.
    func currentOrUpcomingEvent(within minutes: TimeInterval = 60) -> EKEvent? {
        let event = eventsInWindow(minutes: minutes).first
        if let event {
            LogManager.shared.log(
                "Calendar: nearest event within ±\(Int(minutes))m is \"\(event.title ?? "untitled")\" starting \(event.startDate)",
                category: .general
            )
        } else {
            LogManager.shared.log(
                "Calendar: no event within ±\(Int(minutes))m of now",
                category: .general
            )
        }
        return event
    }

    /// All calendar events within ±`minutes` of now, sorted by proximity to now.
    /// Used by the recording toolbar's manual "Match calendar event" picker so
    /// the user can override an incorrect or missed auto-match.
    func eventsInWindow(minutes: TimeInterval = 60) -> [EKEvent] {
        guard authorizationState == .authorized else {
            // .info, not .warning — for users who deliberately denied calendar
            // access this is steady-state, not an anomaly. Repeated toolbar
            // mounts shouldn't spam the warnings channel.
            LogManager.shared.log(
                "Calendar: eventsInWindow(\(Int(minutes))m) skipped — authorization state is \(authorizationState)",
                category: .general
            )
            return []
        }
        let now = Date.now
        let start = now.addingTimeInterval(-minutes * 60)
        let end = now.addingTimeInterval(minutes * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }
        LogManager.shared.log(
            "Calendar: eventsInWindow(±\(Int(minutes))m) found \(events.count) event(s)",
            category: .general
        )
        return events
    }

    /// Extract attendee names from an event.
    func attendeeNames(for event: EKEvent) -> [String] {
        guard let attendees = event.attendees else { return [] }
        return attendees.compactMap { participant in
            if let name = participant.name, !name.isEmpty {
                return name
            }
            if let url = participant.url.absoluteString.components(separatedBy: ":").last,
               url.contains("@") {
                return url
            }
            return nil
        }
    }

    /// Match event attendees to existing Contact records.
    /// Tries exact name/email/alias match first, then falls back to first-name match.
    func matchContacts(attendees: [String], existing: [Contact]) -> [(name: String, contact: Contact?)] {
        attendees.map { name in
            let lowered = name.lowercased()

            let exact = existing.first { contact in
                contact.name.lowercased() == lowered ||
                contact.email?.lowercased() == lowered ||
                contact.speakerAliases.contains(where: { $0.lowercased() == lowered })
            }
            if let exact { return (name, exact) }

            // Fallback: first-name match (handles "Bob" matching "Bob Smith")
            let fn = firstName(from: lowered)
            guard fn.count >= 3 else { return (name, nil) }
            let firstNameMatch = existing.first { contact in
                firstName(from: contact.name.lowercased()) == fn
            }
            return (name, firstNameMatch)
        }
    }

    private func firstName(from fullName: String) -> String {
        fullName.components(separatedBy: " ").first ?? fullName
    }

    /// Get the recurrence identifier for detecting recurring events.
    func recurrenceID(for event: EKEvent) -> String? {
        guard event.hasRecurrenceRules else { return nil }
        return event.calendarItemIdentifier
    }

    /// Find existing meetings with the same recurring event ID and assign a shared series.
    func matchToSeries(
        event: EKEvent,
        meeting: Meeting,
        in context: ModelContext
    ) {
        guard let recurrenceID = recurrenceID(for: event) else { return }

        // Look for existing meetings with this specific recurrence ID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { m in
                m.calendarEventID == recurrenceID
            }
        )
        guard let seriesMeetings = try? context.fetch(descriptor) else { return }

        if let existingSeries = seriesMeetings.first(where: { $0.seriesID != nil }) {
            // Join existing series
            meeting.seriesID = existingSeries.seriesID
            meeting.seriesTitle = existingSeries.seriesTitle ?? event.title
        } else if !seriesMeetings.isEmpty {
            // Create new series from these meetings
            let seriesID = UUID()
            let seriesTitle = event.title ?? "Recurring Meeting"
            meeting.seriesID = seriesID
            meeting.seriesTitle = seriesTitle
            for existing in seriesMeetings {
                existing.seriesID = seriesID
                existing.seriesTitle = seriesTitle
            }
        }
    }

    /// Refresh the current event detection.
    func refreshCurrentEvent() {
        currentEvent = currentOrUpcomingEvent()
    }
}
