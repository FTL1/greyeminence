import Foundation

/// A calendar the user can include/exclude from match lookups.
struct CalendarChoice: Identifiable, Sendable, Hashable {
    /// EventKit `calendarIdentifier` or Microsoft Graph calendar `id`.
    let id: String
    let title: String
    /// Owning account/source, shown as a subtitle (e.g. "iCloud", "Work").
    let account: String
    let source: CalendarEvent.Source
}

/// Persists which calendars are excluded from matching. Opt-out model: a
/// calendar is included unless its identifier is in the disabled set, so newly
/// added calendars are matched by default and an empty/unset preference means
/// "match everything" (the original behavior).
enum CalendarSelection {
    private static let key = "disabledCalendarIDs"

    static func disabledIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func isEnabled(_ id: String) -> Bool {
        !disabledIDs().contains(id)
    }

    static func setEnabled(_ enabled: Bool, id: String) {
        var ids = disabledIDs()
        if enabled { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
