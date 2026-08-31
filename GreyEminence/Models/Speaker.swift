import Foundation
import SwiftUI

enum Speaker: Codable, Hashable, Sendable {
    case me
    /// Local/mic speaker with a persisted display name (session or global default).
    /// Distinct from `.me` so historical "Me" labels stay "Me" until renamed.
    case meNamed(String)
    case other(String)

    static let defaultMeLabel = "Me"

    var displayName: String {
        switch self {
        case .me:
            return SpeakerNames.effectiveMeName ?? Self.defaultMeLabel
        case .meNamed(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? (SpeakerNames.effectiveMeName ?? Self.defaultMeLabel) : trimmed
        case .other(let name):
            return Self.prettyRemoteName(name)
        }
    }

    /// speaker-1, speaker-2, … — one scheme for unnamed remote voices
    /// (live diarization, leftovers after a voice-stamp pass, and legacy
    /// guest-N / unknown-N / "Speaker 2" labels).
    static func placeholderLabel(index: Int) -> String {
        "speaker-\(max(index, 1))"
    }

    static func guestLabel(index: Int) -> String { placeholderLabel(index: index) }

    static func unknownLabel(index: Int) -> String { placeholderLabel(index: index) }

    static func prettyRemoteName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = remoteIndex(fromLegacyName: trimmed) {
            return placeholderLabel(index: number)
        }
        return trimmed
    }

    /// "Speaker" / "Other" / "guest" → 1. "Speaker 2" / "guest-2" / "unknown-2" / "speaker-2" → 2.
    static func remoteIndex(fromLegacyName raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty || lower == "speaker" || lower == "other" || lower == "unknown" || lower == "guest" {
            return 1
        }
        let compact = lower.replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix("speaker") {
            var rest = String(compact.dropFirst(7))
            if rest.hasPrefix("-") { rest.removeFirst() }
            if rest.isEmpty { return 1 }
            if let n = Int(rest), n > 0 { return n }
        }
        if lower.hasPrefix("guest-"), let n = Int(lower.dropFirst(6)), n > 0 {
            return n
        }
        if lower.hasPrefix("unknown-"), let n = Int(lower.dropFirst(8)), n > 0 {
            return n
        }
        return nil
    }

    static func unknownIndex(fromName raw: String) -> Int? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("unknown-"), let n = Int(lower.dropFirst(8)), n > 0 else { return nil }
        return n
    }

    var initials: String {
        if isMe, displayName == Self.defaultMeLabel {
            return "ME"
        }
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var isMe: Bool {
        switch self {
        case .me, .meNamed: true
        case .other: false
        }
    }

    private var storedRemoteName: String? {
        guard case .other(let name) = self else { return nil }
        return name
    }

    /// Generic remote labels that collapse every other person into one identity.
    /// Uses the stored name, not the pretty `speaker-N` display.
    var isAnonymousRemote: Bool {
        guard let name = storedRemoteName else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n.isEmpty || n == "speaker" || n == "other" || n == "unknown"
    }

    /// Temporary diarization slot (speaker-1, guest-1, unknown-1…) — not a name the user chose.
    var isGuestPlaceholder: Bool {
        guard let name = storedRemoteName else { return false }
        if isAnonymousRemote { return true }
        if isUnknownPlaceholder { return true }
        let lower = name.lowercased()
        return Speaker.remoteIndex(fromLegacyName: name) != nil
            || lower.hasPrefix("guest-")
            || lower.hasPrefix("speaker-")
    }

    var isUnknownPlaceholder: Bool {
        guard let name = storedRemoteName else { return false }
        return Speaker.unknownIndex(fromName: name) != nil
    }

    /// Same person for rename-all / hide / merge: any local speaker matches
    /// any other local speaker; remotes match by exact identity or soft name
    /// (Jordan ↔ Jordan Hale). Placeholders never match a real name.
    func matchesIdentity(_ other: Speaker) -> Bool {
        if isMe { return other.isMe }
        if other.isMe { return false }
        if self == other { return true }
        return SpeakerNameMatcher.samePerson(displayName, other.displayName)
    }

    /// Groups `.me` / `.meNamed` as one person for hide/talk-share bookkeeping.
    struct IdentityKey: Hashable, Sendable {
        let isMe: Bool
        let otherName: String?

        /// Stable SwiftUI identity for a hide stub. Must stay in the same
        /// String id space as playable rows (`segment:<uuid>`), never a raw
        /// UUID — LazyVStack recycles mixed UUID/String identities by index
        /// and leaves the first snippet of each speaker on screen.
        var hideStubID: String {
            if isMe { return "hidden:me" }
            return "hidden:\(otherName ?? "")"
        }
    }

    var identityKey: IdentityKey {
        switch self {
        case .me, .meNamed: IdentityKey(isMe: true, otherName: nil)
        case .other(let name): IdentityKey(isMe: false, otherName: SpeakerNameMatcher.normalize(name))
        }
    }

    /// Fallback color when no contact palette is in scope. Prefer
    /// `SpeakerPalette.color(for:contacts:)`.
    var color: Color {
        SpeakerPalette.color(forName: displayName)
    }

    /// Local speaker for new mic segments: session name, then global default, then `.me`.
    static func resolvedMe(
        sessionName: String? = SpeakerNames.sessionMeDisplayName,
        globalName: String? = SpeakerNames.globalMeDisplayName
    ) -> Speaker {
        if let name = SpeakerNames.effectiveMeName(session: sessionName, global: globalName) {
            return .meNamed(name)
        }
        return .me
    }

    /// Build the speaker to apply after the user types a new label.
    /// Empty names are rejected by callers; "me" (any case) restores `.me`.
    static func renamed(from original: Speaker, displayName: String) -> Speaker {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }
        if trimmed.lowercased() == "me" { return .me }
        if original.isMe { return .meNamed(trimmed) }
        return .other(trimmed)
    }

}

/// Share of meeting talk time for one speaker. Uses segment duration when
/// timestamps differ; otherwise falls back to a word-count estimate so
/// live drafts with identical start/end still count.
enum SpeakerTalkShare {
    static func duration(of segment: TranscriptSegment) -> TimeInterval {
        let span = segment.endTime - segment.startTime
        if span > 0.05 { return span }
        let words = segment.text.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }.count
        return TimeInterval(max(words, 1)) * 0.35
    }

    /// 0...100, nearest integer. 0 when the meeting has no measurable talk.
    static func percent(for speaker: Speaker, in segments: [TranscriptSegment]) -> Int {
        var speakerDuration: TimeInterval = 0
        var total: TimeInterval = 0
        for segment in segments {
            let duration = duration(of: segment)
            total += duration
            if segment.speaker.matchesIdentity(speaker) {
                speakerDuration += duration
            }
        }
        guard total > 0 else { return 0 }
        return Int((speakerDuration / total * 100).rounded())
    }

    /// One pass over the transcript so badges don't rescan every line.
    static func percents(in segments: [TranscriptSegment]) -> [Speaker.IdentityKey: Int] {
        var totals: [Speaker.IdentityKey: TimeInterval] = [:]
        var grand: TimeInterval = 0
        for segment in segments {
            let duration = duration(of: segment)
            grand += duration
            totals[segment.speaker.identityKey, default: 0] += duration
        }
        guard grand > 0 else { return [:] }
        return totals.mapValues { Int(($0 / grand * 100).rounded()) }
    }

    /// Speakers with measurable talk, highest share first. Used by the
    /// People header so we only plot people who have actually spoken.
    static func leaders(
        in segments: [TranscriptSegment],
        limit: Int = 3
    ) -> [(speaker: Speaker, percent: Int)] {
        var totals: [Speaker.IdentityKey: (speaker: Speaker, duration: TimeInterval)] = [:]
        var grand: TimeInterval = 0
        for segment in segments {
            let duration = duration(of: segment)
            grand += duration
            let key = segment.speaker.identityKey
            if let existing = totals[key] {
                totals[key] = (existing.speaker, existing.duration + duration)
            } else {
                totals[key] = (segment.speaker, duration)
            }
        }
        guard grand > 0 else { return [] }
        return totals.values
            .map { (speaker: $0.speaker, percent: Int(($0.duration / grand * 100).rounded())) }
            .filter { $0.percent > 0 }
            .sorted { $0.percent > $1.percent }
            .prefix(limit)
            .map { $0 }
    }
}

/// Rewrite guest-N / unknown-N / "Speaker 2" to speaker-1, speaker-2…
/// in first-seen order. A single lumped "Speaker" stays so Recover still
/// appears.
enum SpeakerLegacyMigration {
    static func migrate(_ segments: [TranscriptSegment]) -> Int {
        var firstSeen: [Speaker] = []
        var seen: Set<Speaker> = []
        for segment in segments where !segment.speaker.isMe {
            if seen.insert(segment.speaker).inserted {
                firstSeen.append(segment.speaker)
            }
        }
        if firstSeen.count == 1, firstSeen[0].isAnonymousRemote {
            return 0
        }

        var map: [Speaker: Speaker] = [:]
        var used: Set<Int> = []
        var next = 1
        for speaker in firstSeen {
            guard case .other(let raw) = speaker else { continue }
            guard speaker.isGuestPlaceholder || speaker.isAnonymousRemote else { continue }
            let dest: Speaker
            if raw.lowercased().hasPrefix("speaker-"),
               let n = Speaker.remoteIndex(fromLegacyName: raw),
               !used.contains(n) {
                dest = Speaker.other(Speaker.placeholderLabel(index: n))
                used.insert(n)
                next = max(next, n + 1)
            } else {
                while used.contains(next) { next += 1 }
                dest = Speaker.other(Speaker.placeholderLabel(index: next))
                used.insert(next)
                next += 1
            }
            if dest != speaker { map[speaker] = dest }
        }
        guard !map.isEmpty else { return 0 }
        var changed = 0
        for segment in segments {
            if let dest = map[segment.speaker] {
                segment.speaker = dest
                changed += 1
            }
        }
        return changed
    }
}

/// Find a speaker's lines that contain a query. Used by the speaker menu
/// so search can highlight and jump without filtering the transcript away
/// (which dismissed the menu on the first keystroke).
enum SpeakerSearch {
    static func matchingSegments(
        query: String,
        speaker: Speaker,
        in segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return segments.filter { segment in
            guard segment.speaker.matchesIdentity(speaker) else { return false }
            return segment.text.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    /// First match at or after `startTime`, otherwise the first match.
    static func nearestMatchIndex(in matches: [TranscriptSegment], after startTime: TimeInterval) -> Int {
        guard !matches.isEmpty else { return 0 }
        return matches.firstIndex(where: { $0.startTime >= startTime }) ?? 0
    }
}

/// Keep a named voice from turning into a new guest on the next sentence.
enum SpeakerContinuity {
    /// How long a remote person is assumed to still be talking.
    static let stickyWindow: TimeInterval = 12

    /// Most recent remote speaker whose line ended within `stickyWindow` of `at`.
    static func stickyRemote(
        at time: TimeInterval,
        in segments: [TranscriptSegment],
        window: TimeInterval = stickyWindow
    ) -> Speaker? {
        let remotes = segments.filter { !$0.speaker.isMe && $0.isFinal }
        guard let last = remotes.max(by: { $0.endTime < $1.endTime }) else { return nil }
        if time + 0.05 < last.startTime { return nil }
        if time - last.endTime > window { return nil }
        return last.speaker
    }

    /// Do not let diarization replace "Pat" with a brand-new guest-N.
    /// Guest placeholders may be filled in. Two named people may swap.
    static func resolvedLabel(current: Speaker, proposed: Speaker) -> Speaker {
        if current.isMe { return current }
        if current.isGuestPlaceholder || current.isAnonymousRemote {
            return proposed
        }
        if proposed.isGuestPlaceholder || proposed.isAnonymousRemote {
            return current
        }
        return proposed
    }
}

/// Pick a diarized speaker for a transcript line by time overlap.
enum SpeakerOverlapAssigner {
    static func speaker(
        forStart start: TimeInterval,
        end: TimeInterval,
        in ranges: [(speaker: Speaker, start: TimeInterval, end: TimeInterval)]
    ) -> Speaker? {
        guard !ranges.isEmpty else { return nil }
        let mid = (start + end) / 2
        if let hit = ranges.first(where: { mid >= $0.start && mid <= $0.end }) {
            return hit.speaker
        }
        var best: (speaker: Speaker, distance: TimeInterval)?
        for range in ranges {
            let rangeMid = (range.start + range.end) / 2
            let distance = abs(rangeMid - mid)
            if best == nil || distance < best!.distance {
                best = (range.speaker, distance)
            }
        }
        if let best, best.distance <= 1.5 { return best.speaker }
        return nil
    }
}

/// Soft name match so "Jordan" and "Jordan Hale" hide/bind as one person.
/// Placeholders (guest-N, unknown-N) never match a real name.
enum SpeakerNameMatcher {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func firstToken(_ raw: String) -> String {
        String(normalize(raw).split(separator: " ").first ?? "")
    }

    static func samePerson(_ a: String, _ b: String) -> Bool {
        let left = normalize(a)
        let right = normalize(b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if SpeakerLinkCatalog.isPlaceholder(left) || SpeakerLinkCatalog.isPlaceholder(right) {
            return false
        }
        if left == right { return true }

        let leftParts = left.split(separator: " ")
        let rightParts = right.split(separator: " ")
        if leftParts.count >= 2, rightParts.count >= 2 {
            return leftParts[0] == rightParts[0] && leftParts.last == rightParts.last
        }

        let lf = firstToken(a)
        let rf = firstToken(b)
        if lf.isEmpty || rf.isEmpty { return false }
        if lf == rf { return true }
        // "Jordan" / "Jordan" — require 4 characters so "Ann" ≠ "Anna".
        if lf.count >= 4, rf.hasPrefix(lf) { return true }
        if rf.count >= 4, lf.hasPrefix(rf) { return true }
        return false
    }
}
