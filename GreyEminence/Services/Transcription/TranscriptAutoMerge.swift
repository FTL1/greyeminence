import Foundation

/// Collapse consecutive same-speaker ASR fragments into longer lines.
///
/// A group grows until another speaker talks, the pause between lines
/// exceeds `pause`, or the group's time span exceeds `maxWindow` —
/// whichever comes first. `[Note]` lines never join speech.
enum TranscriptAutoMerge {
    static let defaultMaxWindow: TimeInterval = 15
    static let defaultPause: TimeInterval = 4
    static let nearDuplicateSimilarity = 0.8
    /// ASR often stores endTime == startTime. Treat anything shorter than this
    /// as "no duration" and measure the gap from start to start.
    static let minMeaningfulDuration: TimeInterval = 0.15

    static func isNote(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[Note]")
    }

    /// Time-ordered groups. Groups of one are still returned so callers
    /// can filter `count >= 2` for work.
    static func groups(
        in segments: [TranscriptSegment],
        maxWindow: TimeInterval = defaultMaxWindow,
        pause: TimeInterval = defaultPause
    ) -> [[TranscriptSegment]] {
        let ordered = segments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
            return lhs.endTime < rhs.endTime
        }
        var result: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []

        func flush() {
            if !current.isEmpty { result.append(current) }
            current = []
        }

        for segment in ordered {
            if isNote(segment.text) {
                flush()
                result.append([segment])
                continue
            }
            guard let last = current.last, let first = current.first else {
                current = [segment]
                continue
            }
            let lastEnd = last.endTime > last.startTime + minMeaningfulDuration
                ? last.endTime
                : last.startTime
            let gap = max(0, segment.startTime - lastEnd)
            let spanEnd = max(segment.endTime, segment.startTime)
            let span = spanEnd - first.startTime
            let same = segment.speaker.matchesIdentity(last.speaker)
            if same && gap <= pause && span <= maxWindow {
                current.append(segment)
            } else {
                flush()
                current = [segment]
            }
        }
        flush()
        return result
    }

    /// Join fragment texts, dropping prefix / extension / near-duplicate crumbs.
    static func joinTexts(_ texts: [String]) -> String {
        var result = ""
        for raw in texts {
            let next = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { continue }
            if result.isEmpty {
                result = next
                continue
            }
            switch mergeDecision(existing: result, incoming: next) {
            case .keepExisting:
                continue
            case .replaceWithIncoming:
                result = next
            case .concatenate:
                result += " " + next
            }
        }
        return result
    }

    enum MergeDecision: Equatable {
        case keepExisting
        case replaceWithIncoming
        case concatenate
    }

    static func mergeDecision(existing: String, incoming: String) -> MergeDecision {
        let a = folded(existing)
        let b = folded(incoming)
        if a.isEmpty { return .replaceWithIncoming }
        if b.isEmpty { return .keepExisting }
        if a == b { return .keepExisting }
        if b.hasPrefix(a) { return .replaceWithIncoming }
        if a.hasPrefix(b) { return .keepExisting }
        let similarity = TranscriptDeduplicator.textSimilarity(existing, incoming)
        if similarity >= nearDuplicateSimilarity {
            return incoming.count >= existing.count ? .replaceWithIncoming : .keepExisting
        }
        return .concatenate
    }

    /// Wall-clock end of a merged group: latest real endTime, or the next
    /// line's start when the last crumb has no duration.
    static func coveredEnd(of group: [TranscriptSegment], followingStart: TimeInterval?) -> TimeInterval {
        let start = group.first?.startTime ?? 0
        var end = group.map { max($0.endTime, $0.startTime) }.max() ?? start
        if let last = group.last, last.endTime <= last.startTime + minMeaningfulDuration {
            if let followingStart, followingStart > end {
                end = followingStart
            }
        }
        return max(end, start + 0.4)
    }

    /// End time to play for a displayed line. Truncated auto-merges (endTime
    /// still on the first crumb) play through to the next line.
    static func playbackEnd(segment: TranscriptSegment, nextStart: TimeInterval?) -> TimeInterval {
        var end = max(segment.endTime, segment.startTime)
        if let nextStart, nextStart > segment.startTime {
            let stored = max(0, end - segment.startTime)
            let untilNext = nextStart - segment.startTime
            let looksTruncated = stored < 0.5 || (segment.isEdited && stored + 0.75 < untilNext)
            if looksTruncated {
                end = nextStart
            }
        }
        return max(end, segment.startTime + 0.4)
    }

    static func folded(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.union(.whitespaces).contains($0)
        }
        return String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Enough of a deleted line to put it back after an auto-merge.
struct TranscriptMergeUndoEntry {
    struct KeeperRestore {
        var id: UUID
        var text: String
        var endTime: TimeInterval
        var isEdited: Bool
        var originalText: String?
        var originalSpeakerData: Data?
    }

    struct Deleted {
        var id: UUID
        var speaker: Speaker
        var text: String
        var startTime: TimeInterval
        var endTime: TimeInterval
        var isFinal: Bool
        var isEdited: Bool
        var originalText: String?
        var originalSpeakerData: Data?
        var sectionTag: String?
        var sectionTagID: UUID?
        var confidence: Float
        var createdAt: Date

        static func snapshot(_ segment: TranscriptSegment) -> Deleted {
            Deleted(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                isFinal: segment.isFinal,
                isEdited: segment.isEdited,
                originalText: segment.originalText,
                originalSpeakerData: segment.originalSpeakerData,
                sectionTag: segment.sectionTag,
                sectionTagID: segment.sectionTagID,
                confidence: segment.confidence,
                createdAt: segment.createdAt
            )
        }

        func makeSegment() -> TranscriptSegment {
            let segment = TranscriptSegment(
                speaker: speaker,
                text: text,
                startTime: startTime,
                endTime: endTime,
                isFinal: isFinal
            )
            segment.id = id
            segment.isEdited = isEdited
            segment.originalText = originalText
            segment.originalSpeakerData = originalSpeakerData
            segment.sectionTag = sectionTag
            segment.sectionTagID = sectionTagID
            segment.confidence = confidence
            segment.createdAt = createdAt
            return segment
        }
    }

    var keepers: [KeeperRestore]
    var deleted: [Deleted]
    var retargetedActionItems: [(itemID: UUID, oldSource: UUID?)]
    var removedCount: Int { deleted.count }
}

@Observable
final class TranscriptMergeUndo {
    private(set) var stack: [TranscriptMergeUndoEntry] = []

    var canUndo: Bool { !stack.isEmpty }

    func push(_ entry: TranscriptMergeUndoEntry) {
        stack.append(entry)
        if stack.count > 25 { stack.removeFirst() }
    }

    func pop() -> TranscriptMergeUndoEntry? {
        stack.popLast()
    }

    func clear() {
        stack.removeAll()
    }
}
