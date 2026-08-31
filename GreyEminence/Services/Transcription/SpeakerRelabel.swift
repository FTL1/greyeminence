import Foundation

/// Rules for remapping speakers. Hide / isolate is a reading filter —
/// remapping must never touch a line the user cannot see.
enum SpeakerRelabel {
    /// Lines still shown as real rows (not collapsed hide stubs).
    static func visibleSegments(
        from segments: [TranscriptSegment],
        hiddenSpeakers: [Speaker],
        isolatedSpeaker: Speaker?,
        isolatedSpeakers: [Speaker]? = nil
    ) -> [TranscriptSegment] {
        TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: hiddenSpeakers,
            isolatedSpeaker: isolatedSpeaker,
            searchSpeaker: nil,
            searchQuery: "",
            isolatedSpeakers: isolatedSpeakers
        ).compactMap { item in
            if case .segment(let segment) = item { return segment }
            return nil
        }
    }

    static func visibleIDs(
        from segments: [TranscriptSegment],
        hiddenSpeakers: [Speaker],
        isolatedSpeaker: Speaker?,
        isolatedSpeakers: [Speaker]? = nil
    ) -> Set<UUID> {
        Set(visibleSegments(
            from: segments,
            hiddenSpeakers: hiddenSpeakers,
            isolatedSpeaker: isolatedSpeaker,
            isolatedSpeakers: isolatedSpeakers
        ).map(\.id))
    }

    /// A remote remap must never overwrite Me, even if those lines were
    /// accidentally included in a Select All.
    static func shouldSkip(_ speaker: Speaker, remappingFrom current: Speaker) -> Bool {
        speaker.isMe && !current.isMe
    }

    static func matchesForRelabel(_ segmentSpeaker: Speaker, current: Speaker) -> Bool {
        guard !shouldSkip(segmentSpeaker, remappingFrom: current) else { return false }
        return segmentSpeaker.matchesIdentity(current)
    }

    /// Lines a bulk assign may touch: selected, currently visible, and never
    /// a hidden Me when the new label is someone else.
    static func assignmentTargets(
        selected: Set<UUID>,
        segments: [TranscriptSegment],
        hiddenSpeakers: [Speaker],
        isolatedSpeaker: Speaker?,
        newSpeaker: Speaker,
        isolatedSpeakers: [Speaker]? = nil
    ) -> [TranscriptSegment] {
        let visible = visibleIDs(
            from: segments,
            hiddenSpeakers: hiddenSpeakers,
            isolatedSpeaker: isolatedSpeaker,
            isolatedSpeakers: isolatedSpeakers
        )
        return segments.filter { segment in
            selected.contains(segment.id)
                && visible.contains(segment.id)
                && !(newSpeaker.isMe == false && segment.speaker.isMe)
        }
    }
}

/// Snapshots of who said what, so a bad remap can be undone.
@Observable
final class SpeakerLabelUndo {
    private(set) var stack: [[UUID: Speaker]] = []

    var canUndo: Bool { !stack.isEmpty }

    func capture(_ segments: [TranscriptSegment]) {
        let shot = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0.speaker) })
        stack.append(shot)
        if stack.count > 25 { stack.removeFirst() }
    }

    func pop() -> [UUID: Speaker]? {
        stack.popLast()
    }

    func clear() {
        stack.removeAll()
    }

    static func apply(_ labels: [UUID: Speaker], to segments: [TranscriptSegment]) {
        for segment in segments {
            if let speaker = labels[segment.id] {
                segment.speaker = speaker
            }
        }
    }
}
