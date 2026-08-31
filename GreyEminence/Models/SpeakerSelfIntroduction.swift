import Foundation

/// When a remote voice names themselves in the intro ("I'm Bob Dipshit"),
/// that voice is Bob. Does not run on Me, and does not treat "this is Bob"
/// (someone else introducing him) as a claim.
enum SpeakerSelfIntroduction {
    static let introWindow: TimeInterval = 8 * 60

    private static let firstPerson =
        #"\b(?:I['’]m|I am|my name is|I['’]m called)\s+([A-Za-z][A-Za-z.'\-]{1,}(?:\s+[A-Za-z][A-Za-z.'\-]{1,}){0,2})"#

    private static let stopwords: Set<String> = [
        "going", "gonna", "gone", "just", "not", "no", "here", "sorry",
        "thinking", "trying", "looking", "wondering", "good", "fine", "well",
        "so", "also", "actually", "really", "still", "back", "very", "doing",
        "calling", "taking", "making", "getting", "putting", "coming", "leaving",
        "using", "working", "talking", "saying", "asking", "kinda", "sure",
        "afraid", "glad", "happy", "ready", "done", "all", "about", "from",
        "with", "like", "that", "this", "there", "yeah", "yes", "okay", "ok",
        "hi", "hey", "hello", "thanks", "thank", "please", "maybe", "probably",
    ]

    /// First-person self-name in `text`, or nil.
    static func claimedName(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: firstPerson, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: full),
              match.numberOfRanges >= 2 else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = captured.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        if stopwords.contains(first.lowercased()) { return nil }
        if first.count < 2 { return nil }
        return words.map { word in
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".'-"))
            guard let firstChar = trimmed.first else { return word }
            if trimmed.count <= 4, trimmed.uppercased() == trimmed {
                return trimmed.uppercased()
            }
            return String(firstChar).uppercased() + trimmed.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Rename placeholder voices that named themselves. Prefers a calendar
    /// invitee when the claimed name matches one. Returns how many lines changed.
    static func apply(
        segments: [TranscriptSegment],
        inviteeNames: [String],
        myLabels: [String] = [],
        window: TimeInterval = introWindow
    ) -> Int {
        let invitees = inviteeNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var assigned: [Speaker.IdentityKey: String] = [:]
        var changed = 0
        let ordered = segments.sorted { $0.startTime < $1.startTime }
        for segment in ordered {
            guard segment.speaker.isGuestPlaceholder else { continue }
            guard segment.startTime <= window else { continue }
            guard let claimed = claimedName(in: segment.text) else { continue }
            if myLabels.contains(where: { SpeakerNameMatcher.samePerson($0, claimed) }) {
                continue
            }
            let resolved = resolvedInvitee(claimed, invitees: invitees) ?? claimed
            assigned[segment.speaker.identityKey] = resolved
        }
        guard !assigned.isEmpty else { return 0 }
        for segment in segments {
            guard let name = assigned[segment.speaker.identityKey] else { continue }
            let dest = Speaker.other(name)
            if dest != segment.speaker {
                segment.speaker = dest
                changed += 1
            }
        }
        return changed
    }

    private static func resolvedInvitee(_ claimed: String, invitees: [String]) -> String? {
        if let exact = invitees.first(where: { SpeakerNameMatcher.samePerson($0, claimed) }) {
            return exact
        }
        let claimedFirst = SpeakerNameMatcher.firstToken(claimed)
        guard claimedFirst.count >= 3 else { return nil }
        let hits = invitees.filter { SpeakerNameMatcher.firstToken($0) == claimedFirst }
        return hits.count == 1 ? hits[0] : nil
    }
}
