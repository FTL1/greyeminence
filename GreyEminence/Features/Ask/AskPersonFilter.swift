import Foundation

/// Detects a person named in a question so the name can become a *filter*
/// rather than a search term.
///
/// The problem this solves: "what did Stephen Smith say about X" returns the
/// passages where somebody said Stephen's name, not the passages where he
/// discussed X. BM25 treats a proper noun as a high-IDF token and rewards it
/// heavily, and diarization labels speakers "Speaker 3" rather than by name,
/// so the name carries no attribution signal at all — only noise.
///
/// So: resolve the name against the contact roster, narrow the candidate set
/// to meetings that person attended, and search the *remaining* words. The
/// person becomes a where-clause; the concept keeps the whole query.
enum AskPersonFilter {
    /// One person the roster can match, with every string that should resolve
    /// to them (full name, nickname, speaker aliases).
    struct Candidate: Equatable {
        let canonicalName: String
        let aliases: [String]

        init(canonicalName: String, aliases: [String] = []) {
            self.canonicalName = canonicalName
            self.aliases = aliases
        }

        /// Every string that should resolve to this person: the full name,
        /// any explicit alias, and — implicitly — their first and last name on
        /// their own, because "what did Erin say" is how people actually ask.
        /// A bare given name is only ever accepted alongside an attribution
        /// cue, so deriving these doesn't loosen the guard.
        var aliasTokens: [[String]] {
            var result = ([canonicalName] + aliases)
                .map(AskPersonFilter.tokens)
                .filter { !$0.isEmpty }

            let full = AskPersonFilter.tokens(canonicalName)
            if full.count >= 2 {
                for part in [full[0], full[full.count - 1]] where !result.contains([part]) {
                    result.append([part])
                }
            }
            return result
        }
    }

    struct Detection: Equatable {
        /// Canonical names, in the order they appear in the query.
        var names: [String]
        /// The query with the person references removed — what actually gets
        /// embedded and BM25'd.
        var strippedQuery: String
    }

    /// Words that signal the question is *about what a person said*. A
    /// single-token name only counts as a person reference in their company,
    /// which is what keeps "can you mark that as done" from resolving to a
    /// colleague named Mark.
    private static let attributionCues: Set<String> = [
        "said", "say", "says", "saying", "mentioned", "mention", "mentions",
        "asked", "asks", "ask", "raised", "raise", "noted", "told", "tell",
        "thinks", "think", "thought", "thoughts", "wants", "wanted", "suggested",
        "suggests", "proposed", "proposes", "commented", "comment", "opinion",
        "position", "take", "view", "feedback", "concern", "concerns",
        "according", "per", "from", "with", "by", "about",
    ]

    /// Given names that are also ordinary English words. These resolve only
    /// when the query capitalizes them, so a sentence that merely uses the
    /// word doesn't silently narrow the search to one person's meetings.
    /// Deliberately short. Every entry costs a real miss — a colleague whose
    /// name lands here stops resolving from a lowercase question — so it holds
    /// only words whose ordinary-English use in a query genuinely outweighs
    /// their use as a name. Names that merely *could* be words (Gene, Ray,
    /// Max, Frank, Penny) are left out: the filter is shown in the UI, so a
    /// wrong narrowing is visible and recoverable, while a silent miss just
    /// looks like bad search.
    private static let ambiguousGivenNames: Set<String> = [
        "will", "may", "mark", "bill", "art", "grant", "hope", "rich",
        "chase", "chance", "drew", "rose", "dawn", "joy", "faith",
        "summer", "sunny",
    ]

    /// Scan `query` for anyone in `roster`. Returns nil when nobody resolves —
    /// the caller then searches the question exactly as asked.
    static func detect(in query: String, roster: [Candidate]) -> Detection? {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return nil }
        let tokenSet = Set(queryTokens)
        let hasCue = queryTokens.contains { attributionCues.contains($0) }

        // Longest alias first: "Stephen Smith" must win over a bare "Stephen"
        // so the whole name is stripped and the right person resolves.
        var matches: [(position: Int, name: String, span: [String])] = []
        for candidate in roster {
            var best: (position: Int, span: [String])?
            for alias in candidate.aliasTokens.sorted(by: { $0.count > $1.count }) {
                guard let position = firstIndex(of: alias, in: queryTokens) else { continue }
                guard accepts(alias: alias, query: query, hasCue: hasCue, tokenSet: tokenSet) else { continue }
                if best == nil || alias.count > best!.span.count {
                    best = (position, alias)
                }
            }
            if let best {
                matches.append((best.position, candidate.canonicalName, best.span))
            }
        }
        guard !matches.isEmpty else { return nil }

        matches.sort { $0.position < $1.position }
        var seen = Set<String>()
        let names = matches.map(\.name).filter { seen.insert($0).inserted }

        return Detection(
            names: names,
            strippedQuery: strip(spans: matches.map(\.span), from: query)
        )
    }

    /// A multi-token alias is a person reference on its own. A single token
    /// needs an attribution cue, and an ordinary-word name needs the query to
    /// have capitalized it as well.
    private static func accepts(alias: [String], query: String, hasCue: Bool, tokenSet: Set<String>) -> Bool {
        guard alias.count == 1 else { return true }
        guard let token = alias.first else { return false }
        // "with"/"from"/"about" are cues, but a name that IS one of those words
        // must not vouch for itself.
        guard hasCue, !attributionCues.contains(token) else { return false }
        guard ambiguousGivenNames.contains(token) else { return true }
        return containsCapitalized(token, in: query)
    }

    private static func containsCapitalized(_ token: String, in query: String) -> Bool {
        let capitalized = token.prefix(1).uppercased() + token.dropFirst()
        return rawTokens(query).contains(capitalized)
    }

    /// Remove each matched span from the query, preserving everything else.
    private static func strip(spans: [[String]], from query: String) -> String {
        let raw = rawTokens(query)
        var drop = Set<Int>()
        for span in spans {
            var index = 0
            while index + span.count <= raw.count {
                let window = raw[index..<(index + span.count)].map { $0.lowercased() }
                if window == span {
                    for offset in 0..<span.count { drop.insert(index + offset) }
                    index += span.count
                } else {
                    index += 1
                }
            }
        }
        let kept = raw.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        return kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenizing

    /// Words as written, so capitalization survives for the ambiguity check.
    /// A possessive is reduced to the name itself: "Stephen's" tokenizes as
    /// "Stephen", so it matches the roster and gets stripped along with the
    /// rest of the reference.
    private static func rawTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        var characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "\u{2019}" {
                // Trailing "'s" ends the word without becoming part of it;
                // an internal apostrophe (O'Brien) keeps the token together.
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let after = index + 2 < characters.count ? characters[index + 2] : nil
                if let next, next == "s" || next == "S", after == nil || !(after!.isLetter || after!.isNumber) {
                    flush()
                    index += 2
                    continue
                }
            } else {
                flush()
            }
            index += 1
        }
        flush()
        return tokens
    }

    static func tokens(_ text: String) -> [String] {
        rawTokens(text).map { $0.lowercased() }
    }

    private static func firstIndex(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
    }
}
