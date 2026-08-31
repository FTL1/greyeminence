import Foundation

/// People, speakers, and actions rolled up from a set of topic meetings.
enum TopicMapRoster {
    struct Person: Identifiable, Hashable {
        let id: UUID
        let name: String
        let meetingCount: Int
        let actionCount: Int
        let meetingIDs: Set<UUID>
    }

    struct SpeakerRow: Identifiable, Hashable {
        let id: String
        let displayName: String
        let isMe: Bool
        let meetingCount: Int
        let talkPercent: Int
        let meetingIDs: Set<UUID>
    }

    static func uniqueMeetings(from topicMeetings: [String: [Meeting]]) -> [Meeting] {
        var seen = Set<UUID>()
        var unique: [Meeting] = []
        for meetings in topicMeetings.values {
            for meeting in meetings where seen.insert(meeting.id).inserted {
                unique.append(meeting)
            }
        }
        return unique
    }

    static func people(in meetings: [Meeting]) -> [Person] {
        struct Acc {
            var name: String
            var meetings: Set<UUID>
            var actions: Int
        }
        var byID: [UUID: Acc] = [:]
        for meeting in meetings {
            for contact in meeting.attendees where !contact.isArchived {
                var acc = byID[contact.id] ?? Acc(name: contact.name, meetings: [], actions: 0)
                acc.name = contact.name
                acc.meetings.insert(meeting.id)
                byID[contact.id] = acc
            }
            for item in meeting.actionItems {
                if let contact = item.assignedContact, !contact.isArchived {
                    var acc = byID[contact.id] ?? Acc(name: contact.name, meetings: [], actions: 0)
                    acc.actions += 1
                    acc.meetings.insert(meeting.id)
                    byID[contact.id] = acc
                }
            }
        }
        return byID.map { id, acc in
            Person(
                id: id,
                name: acc.name,
                meetingCount: acc.meetings.count,
                actionCount: acc.actions,
                meetingIDs: acc.meetings
            )
        }
        .sorted {
            if $0.meetingCount != $1.meetingCount { return $0.meetingCount > $1.meetingCount }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func speakers(in meetings: [Meeting]) -> [SpeakerRow] {
        struct Acc {
            var displayName: String
            var isMe: Bool
            var talk: TimeInterval
            var meetings: Set<UUID>
        }
        var byToken: [String: Acc] = [:]
        var grand: TimeInterval = 0
        for meeting in meetings {
            for segment in meeting.segments {
                let duration = SpeakerTalkShare.duration(of: segment)
                grand += duration
                let token = speakerToken(segment.speaker)
                var acc = byToken[token] ?? Acc(
                    displayName: segment.speaker.displayName,
                    isMe: segment.speaker.isMe,
                    talk: 0,
                    meetings: []
                )
                acc.talk += duration
                acc.meetings.insert(meeting.id)
                if segment.speaker.displayName.count >= acc.displayName.count {
                    acc.displayName = segment.speaker.displayName
                }
                byToken[token] = acc
            }
        }
        return byToken.map { token, acc in
            SpeakerRow(
                id: token,
                displayName: acc.displayName,
                isMe: acc.isMe,
                meetingCount: acc.meetings.count,
                talkPercent: grand > 0 ? Int((acc.talk / grand * 100).rounded()) : 0,
                meetingIDs: acc.meetings
            )
        }
        .sorted {
            if $0.talkPercent != $1.talkPercent { return $0.talkPercent > $1.talkPercent }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func actions(in meetings: [Meeting]) -> [ActionItem] {
        meetings.flatMap(\.actionItems).sorted { a, b in
            let ar = rank(a), br = rank(b)
            if ar != br { return ar < br }
            switch (a.dueDate, b.dueDate) {
            case let (.some(x), .some(y)): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.createdAt > b.createdAt
            }
        }
    }

    static func topTopics(
        meetingIDs: Set<UUID>,
        topicMeetings: [String: [Meeting]],
        limit: Int = 8
    ) -> [(label: String, count: Int)] {
        topicMeetings.compactMap { label, meetings -> (String, Int)? in
            let count = meetings.filter { meetingIDs.contains($0.id) }.count
            return count > 0 ? (label, count) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map { (label: $0.0, count: $0.1) }
    }

    static func speakerToken(_ speaker: Speaker) -> String {
        if speaker.isMe { return "me" }
        return Speaker.prettyRemoteName(speaker.displayName).lowercased()
    }

    private static func rank(_ item: ActionItem) -> Int {
        if item.isDismissed { return 2 }
        if item.isCompleted { return 1 }
        return 0
    }
}
