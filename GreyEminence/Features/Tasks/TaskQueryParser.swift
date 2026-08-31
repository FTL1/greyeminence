import Foundation

/// Turns a short English request into Tasks filters.
/// Covers phrases like "past 30 days", "last month", "dropped", "stalled".
enum TaskQueryParser {
    struct Result: Equatable {
        var since: Date?
        var until: Date?
        var onlyStalled: Bool = false
        var people: PeopleHint = .unchanged
        var meetingHint: String?

        enum PeopleHint: Equatable {
            case unchanged
            case mine
            case all
        }
    }

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Result? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        var result = Result()

        if lowered.contains("stalled") || lowered.contains("dropped") || lowered.contains("overdue") {
            result.onlyStalled = true
        }

        if lowered.contains("everyone") || lowered.contains("all assignees") || lowered.contains("all people") {
            result.people = .all
        } else if lowered.contains("mine") || lowered.contains("my action") || lowered.contains("assigned to me") {
            result.people = .mine
        }

        if let days = firstInt(after: ["past ", "last "], in: lowered),
           lowered.contains("day") {
            result.since = calendar.date(byAdding: .day, value: -days, to: now)
        } else if let weeks = firstInt(after: ["past ", "last "], in: lowered),
                  lowered.contains("week") {
            result.since = calendar.date(byAdding: .day, value: -(weeks * 7), to: now)
        } else if lowered.contains("last month") || lowered.contains("past month") {
            result.since = calendar.date(byAdding: .month, value: -1, to: now)
        } else if let months = firstInt(after: ["past ", "last "], in: lowered),
                  lowered.contains("month") {
            result.since = calendar.date(byAdding: .month, value: -months, to: now)
        } else if lowered.contains("this week") {
            result.since = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        } else if lowered.contains("this month") {
            result.since = calendar.dateInterval(of: .month, for: now)?.start
        }

        if result.since == nil && result.onlyStalled == false && result.people == .unchanged {
            // Bare series / title fragment, e.g. "Weekly Standup"
            if !lowered.contains("action") && text.count >= 3 {
                result.meetingHint = text
            } else {
                return nil
            }
        }

        return result
    }

    private static func firstInt(after prefixes: [String], in text: String) -> Int? {
        for prefix in prefixes {
            guard let range = text.range(of: prefix) else { continue }
            let rest = text[range.upperBound...]
            let digits = rest.prefix(while: { $0.isNumber })
            if let value = Int(digits), value > 0 { return value }
        }
        return nil
    }
}
