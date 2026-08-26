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
        return wordSpans(query).contains { $0.text == capitalized }
    }

    /// Remove each matched span from the query.
    ///
    /// Splices the original string rather than rebuilding it from tokens, so
    /// contractions and punctuation survive: rebuilding turned "we couldn't
    /// process" into "we couldnt process", and "couldnt" matches nothing in
    /// the index.
    private static func strip(spans: [[String]], from query: String) -> String {
        let words = wordSpans(query)
        var cut: [Range<String.Index>] = []
        for span in spans {
            var index = 0
            while index + span.count <= words.count {
                let window = words[index..<(index + span.count)].map { $0.text.lowercased() }
                if window == span {
                    cut.append(words[index].range.lowerBound..<words[index + span.count - 1].range.upperBound)
                    index += span.count
                } else {
                    index += 1
                }
            }
        }
        guard !cut.isEmpty else { return query }

        var output = query
        for range in cut.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            output.replaceSubrange(range, with: "")
        }
        return output
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:?!])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenizing

    private struct WordSpan {
        let text: String
        let range: Range<String.Index>
    }

    /// Words as written, with their ranges, so capitalization survives for the
    /// ambiguity check and the original string can be spliced.
    ///
    /// A trailing possessive ends the word without joining it: "Stephen's"
    /// yields "Stephen" (spanning the apostrophe-s, so stripping removes the
    /// whole reference). An internal apostrophe keeps a token together, which
    /// is what "O'Brien" and "couldn't" both need.
    private static func wordSpans(_ text: String) -> [WordSpan] {
        var spans: [WordSpan] = []
        var current = ""
        var start: String.Index?
        var index = text.startIndex

        func flush(end: String.Index) {
            guard !current.isEmpty, let begin = start else { current = ""; start = nil; return }
            spans.append(WordSpan(text: current, range: begin..<end))
            current = ""
            start = nil
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isLetter || character.isNumber {
                if start == nil { start = index }
                current.append(character)
            } else if character == "'" || character == "\u{2019}" {
                let following = next < text.endIndex ? text[next] : nil
                let after = next < text.endIndex ? text.index(after: next) : text.endIndex
                let afterCharacter = after < text.endIndex ? text[after] : nil
                let isPossessive = (following == "s" || following == "S")
                    && !(afterCharacter?.isLetter ?? false)
                    && !(afterCharacter?.isNumber ?? false)
                if isPossessive {
                    flush(end: after)
                    index = after
                    continue
                }
                // Internal apostrophe — part of the word.
                if start == nil { start = index }
                current.append(character)
            } else {
                flush(end: index)
            }
            index = next
        }
        flush(end: text.endIndex)
        return spans
    }

    static func tokens(_ text: String) -> [String] {
        wordSpans(text).map { $0.text.replacingOccurrences(of: "'", with: "").lowercased() }
    }

    private static func firstIndex(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
    }
}
