import Foundation

enum InsightScope: String, CaseIterable, Sendable, Identifiable {
    case full
    case summary
    case followUps
    case actionItems
    case topics

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Meeting Intelligence"
        case .summary: "Summary"
        case .followUps: "Follow-up Questions"
        case .actionItems: "Action Items"
        case .topics: "Topics"
        }
    }

    var promptName: String {
        switch self {
        case .full: "the whole meeting"
        case .summary: "the summary only"
        case .followUps: "follow-up questions only"
        case .actionItems: "action items only"
        case .topics: "topics only"
        }
    }
}

enum InsightDepth: String, CaseIterable, Sendable {
    case standard
    case deep
    case deepest
    case revert

    var label: String {
        switch self {
        case .standard: "Reanalyze"
        case .deep: "Deep"
        case .deepest: "Deepest"
        case .revert: "Revert"
        }
    }
}

enum InsightRevision {
    struct ActionSnapshot: Codable, Sendable {
        var text: String
        var assignee: String?
        var isCompleted: Bool
    }

    static func encodeActions(_ items: [ParsedActionItem]) -> String? {
        let snaps = items.map { ActionSnapshot(text: $0.text, assignee: $0.assignee, isCompleted: false) }
        guard let data = try? JSONEncoder().encode(snaps) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encodeMeetingActions(_ items: [ActionItem]) -> String? {
        let snaps = items.map {
            ActionSnapshot(text: $0.text, assignee: $0.displayAssignee ?? $0.assignee, isCompleted: $0.isCompleted)
        }
        guard let data = try? JSONEncoder().encode(snaps) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeActions(_ json: String?) -> [ParsedActionItem] {
        guard let json, let data = json.data(using: .utf8),
              let snaps = try? JSONDecoder().decode([ActionSnapshot].self, from: data) else {
            return []
        }
        return snaps.map { ParsedActionItem(text: $0.text, assignee: $0.assignee, sourceQuote: nil) }
    }

    static func history(for meeting: Meeting) -> [MeetingInsight] {
        meeting.insights.sorted { $0.createdAt > $1.createdAt }
    }

    static func canRevert(_ meeting: Meeting) -> Bool {
        meeting.insights.count >= 2
    }

    static func previousInsight(for meeting: Meeting, scope: InsightScope, after current: MeetingInsight? = nil) -> MeetingInsight? {
        let items = history(for: meeting)
        let start = current ?? items.first
        let older = items.filter { insight in
            guard let start else { return true }
            return insight.createdAt < start.createdAt || (insight.createdAt == start.createdAt && insight.id != start.id)
        }
        if scope == .full {
            return older.first
        }
        return older.first { insight in
            insight.scopeRaw == scope.rawValue || insight.scopeRaw == InsightScope.full.rawValue || insight.scopeRaw == nil
        }
    }
}
