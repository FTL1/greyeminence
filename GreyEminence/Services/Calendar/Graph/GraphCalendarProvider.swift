import Foundation

/// Reads the connected Microsoft 365 account's calendar via Graph's
/// `/me/calendarView` (which expands recurring events into per-occurrence
/// instances). Self-gating: returns `[]` unless a real client ID is configured,
/// the user has enabled the integration, and a valid token is available — so a
/// network/token failure can never drop the local EventKit results.
@MainActor
final class GraphCalendarProvider {
    func eventsInWindow(minutes: TimeInterval, around: Date = Date.now) async -> [CalendarEvent] {
        guard GraphConfig.isConfigured,
              UserDefaults.standard.bool(forKey: GraphConfig.enabledKey),
              let token = await GraphAuthService.shared.validAccessToken() else {
            return []
        }
        // Query the user-selected calendars (each scoped fetch expands its own
        // recurrences). If we can't list calendars, fall back to the default
        // calendar view (nil) so the integration still works.
        let calendars = (try? await listCalendars(token: token)) ?? []
        let targets: [String?]
        if calendars.isEmpty {
            targets = [nil]
        } else {
            let disabled = CalendarSelection.disabledIDs()
            targets = calendars.filter { !disabled.contains($0.id) }.map { Optional($0.id) }
        }

        // Fetch the calendars concurrently; one calendar failing yields [] for
        // that calendar without dropping the others.
        let events = await withTaskGroup(of: [CalendarEvent].self) { group in
            for calendarID in targets {
                group.addTask {
                    (try? await Self.fetchCalendarView(calendarID: calendarID, minutes: minutes, token: token, around: around)) ?? []
                }
            }
            var all: [CalendarEvent] = []
            for await chunk in group { all += chunk }
            return all
        }
        LogManager.send(
            "Graph: fetched \(events.count) event(s) within ±\(Int(minutes))m across \(targets.count) calendar(s)",
            category: .general
        )
        return events
    }

    /// The connected account's calendars, for the Settings selection list.
    func availableCalendars() async -> [CalendarChoice] {
        guard GraphConfig.isConfigured,
              UserDefaults.standard.bool(forKey: GraphConfig.enabledKey),
              let token = await GraphAuthService.shared.validAccessToken() else {
            return []
        }
        return (try? await listCalendars(token: token)) ?? []
    }

    nonisolated private func listCalendars(token: String) async throws -> [CalendarChoice] {
        let data = try await Self.graphGET(
            path: "/me/calendars",
            queryItems: [.init(name: "$select", value: "id,name,owner"), .init(name: "$top", value: "50")],
            token: token
        )
        return try JSONDecoder().decode(GraphCalendarsResponse.self, from: data).value.map {
            CalendarChoice(
                id: $0.id,
                title: $0.name ?? "Calendar",
                account: $0.owner?.name ?? $0.owner?.address ?? "Microsoft 365",
                source: .microsoftGraph
            )
        }
    }

    /// Calendar view for a specific calendar (`nil` = the account's default),
    /// centered on `around` (now for live matching, the meeting date for post-hoc).
    nonisolated private static func fetchCalendarView(calendarID: String?, minutes: TimeInterval, token: String, around: Date) async throws -> [CalendarEvent] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        let path = calendarID.map { "/me/calendars/\($0)/calendarView" } ?? "/me/calendarView"
        let data = try await graphGET(
            path: path,
            queryItems: [
                .init(name: "startDateTime", value: iso.string(from: around.addingTimeInterval(-minutes * 60))),
                .init(name: "endDateTime", value: iso.string(from: around.addingTimeInterval(minutes * 60))),
                .init(name: "$select", value: "subject,start,end,attendees,organizer,seriesMasterId,type,isAllDay,isCancelled"),
                .init(name: "$orderby", value: "start/dateTime"),
                .init(name: "$top", value: "50"),
            ],
            // Return all times in UTC so we can parse them without per-event zones.
            headers: ["Prefer": "outlook.timezone=\"UTC\""],
            token: token
        )
        return try decodeEvents(from: data)
    }

    /// Shared GET against the Graph base URL: builds the request, attaches the
    /// bearer token + any extra headers, and validates the response status.
    nonisolated private static func graphGET(
        path: String,
        queryItems: [URLQueryItem],
        headers: [String: String] = [:],
        token: String
    ) async throws -> Data {
        var comps = URLComponents(string: "\(GraphConfig.graphBaseURL)\(path)")!
        comps.queryItems = queryItems
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Graph", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return data
    }

    /// Decode a Graph `/me/calendarView` response body into neutral events.
    /// Pure + `nonisolated` so it's callable off the main actor and from tests.
    nonisolated static func decodeEvents(from data: Data) throws -> [CalendarEvent] {
        try JSONDecoder().decode(GraphCalendarResponse.self, from: data).value.compactMap(map)
    }

    nonisolated private static func map(_ ev: GraphEvent) -> CalendarEvent? {
        // All-day events (vacations, holidays) aren't meetings — skip them.
        guard !(ev.isAllDay ?? false) else { return nil }
        guard let startStr = ev.start?.dateTime, let start = parseDate(startStr) else { return nil }
        let end = (ev.end?.dateTime).flatMap(parseDate) ?? start
        // Treat as recurring only when we actually have a series key to group by.
        // A recurring occurrence without `seriesMasterId` has no stable
        // cross-occurrence id, so series-match it as a one-off (linkIdentifier =
        // its own id) rather than keying every occurrence to a different value.
        let isRecurring = ev.seriesMasterId != nil
        var attendees = (ev.attendees ?? []).compactMap { att -> EventAttendee? in
            // Conference rooms come through as type "resource" — not people.
            guard att.type?.lowercased() != "resource" else { return nil }
            return EventAttendee.resolve(name: att.emailAddress?.name, email: att.emailAddress?.address)
        }
        if let organizer = EventAttendee.resolve(
            name: ev.organizer?.emailAddress?.name,
            email: ev.organizer?.emailAddress?.address
        ), !attendees.contains(where: {
            if let a = $0.email, let b = organizer.email, a == b { return true }
            return $0.name.compare(organizer.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            attendees.insert(organizer, at: 0)
        }
        return CalendarEvent(
            id: ev.id,
            linkIdentifier: ev.seriesMasterId ?? ev.id,
            title: ev.subject,
            startDate: start,
            endDate: end,
            attendees: attendees,
            isRecurring: isRecurring,
            isCancelled: ev.isCancelled == true
                || CalendarEvent.titleIndicatesCancellation(ev.subject),
            source: .microsoftGraph
        )
    }

    /// Graph returns e.g. "2026-06-01T15:00:00.0000000" (UTC via the Prefer
    /// header). Drop the fractional seconds and parse as UTC. A fresh formatter
    /// per call keeps this `nonisolated` without a shared non-Sendable static.
    nonisolated private static func parseDate(_ value: String) -> Date? {
        let withoutFraction = value.split(separator: ".").first.map(String.init) ?? value
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: withoutFraction)
    }
}

// MARK: - Graph JSON

private struct GraphCalendarResponse: Decodable {
    let value: [GraphEvent]
}

private struct GraphCalendarsResponse: Decodable {
    let value: [GraphCalendarItem]
}

private struct GraphCalendarItem: Decodable {
    let id: String
    let name: String?
    let owner: GraphEmailAddress?
}

struct GraphEvent: Decodable {
    let id: String
    let subject: String?
    let type: String?
    let seriesMasterId: String?
    let start: GraphDateTime?
    let end: GraphDateTime?
    let attendees: [GraphAttendee]?
    let organizer: GraphOrganizer?
    let isAllDay: Bool?
    let isCancelled: Bool?
}

struct GraphOrganizer: Decodable {
    let emailAddress: GraphEmailAddress?
}

struct GraphDateTime: Decodable {
    let dateTime: String
    let timeZone: String?
}

struct GraphAttendee: Decodable {
    /// "required" | "optional" | "resource" (rooms/equipment).
    let type: String?
    let emailAddress: GraphEmailAddress?
}

struct GraphEmailAddress: Decodable {
    let name: String?
    let address: String?
}
