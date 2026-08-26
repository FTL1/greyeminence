import Foundation

/// Pure prompt construction for the Ask conversation. Kept free of SwiftData
/// and AppKit so the tricky parts — what gets carried forward between turns,
/// how much history survives trimming — are testable directly.
enum AskPromptBuilder {
    static let system = """
    You help the user recall and reason about their own past meetings.

    You are given numbered snippets retrieved from transcripts, screen-share \
    observations, and session recaps. Ground every claim in those snippets and \
    cite them inline as [3] or [3, 7]. The numbers are stable for the whole \
    conversation: a snippet keeps its number in later answers, and snippets \
    from earlier turns stay valid to cite.

    Rules:
    - Never invent meetings, people, dates, or commitments that the snippets \
    do not support. If the snippets don't cover the question, say so plainly \
    and suggest a sharper question or a wider date range.
    - Transcripts are machine-generated and contain misrecognitions. Read \
    through obvious errors, but don't build a conclusion on a single garbled line.
    - Answer conversationally and get to the point. This is a dialogue, not a \
    report: no headings or preamble for a short answer, and no restating the \
    question back.
    - When the user follows up, treat it as continuing the same thread rather \
    than a fresh question.
    """

    /// Turns a context-dependent follow-up into a query the retriever can use.
    ///
    /// This matters more than it looks. Retrieval here is BM25 plus weak
    /// on-device embeddings, and a follow-up like "what did she say about
    /// that?" carries almost no searchable signal — the nouns all live in
    /// earlier turns. Rewriting recovers them before the search runs.
    static func condensePrompt(history: [AskTurn], question: String) -> String {
        let recent = history.suffix(4).map { turn in
            var block = "Q: \(turn.question)"
            if let answer = turn.answer {
                block += "\nA: \(answer.prefix(400))"
            }
            return block
        }.joined(separator: "\n\n")

        return """
        Rewrite the user's latest message as a standalone search query over a \
        corpus of meeting transcripts.

        CONVERSATION SO FAR:
        \(recent)

        LATEST MESSAGE:
        \(question)

        Resolve pronouns and references against the conversation, and keep the \
        concrete nouns — names, projects, systems, decisions — because the search \
        is keyword-sensitive. Output only the query text: no quotes, no preamble, \
        no explanation. If the latest message is already self-contained, output it \
        unchanged.
        """
    }

    /// The condenser occasionally editorialises despite instructions. A reply
    /// that is very long, or that has clearly answered rather than rewritten,
    /// is discarded in favour of the raw question.
    static func sanitizeCondensed(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !cleaned.isEmpty, cleaned.count <= 300, !cleaned.contains("\n\n") else {
            return fallback
        }
        return cleaned
    }

    /// Numbered snippet block for the current turn.
    static func sourcesBlock(_ sources: [AskSource], leadIns: [String: String] = [:]) -> String {
        sources.map { source in
            let result = source.result
            let date = DateFormatter.shortDate.string(from: result.meetingDate)
            let kind = kindLabel(result.sourceKind)
            var block = "[\(source.number)] \(kind) — \(result.meetingTitle), \(date)"
            if let lead = leadIns[source.id], !lead.isEmpty {
                block += "\n\(lead)"
            }
            block += "\n\(result.text)"
            return block
        }.joined(separator: "\n\n")
    }

    private static func kindLabel(_ kind: EmbeddingRecord.SourceKind) -> String {
        switch kind {
        case .transcriptSegment: "transcript"
        case .actionItem: "task"
        case .followUpQuestion: "open question"
        case .meetingSummary: "summary"
        case .screenObservation: "screen share"
        case .sessionNarrative: "screen-share recap"
        }
    }

    /// Build the message array for a turn.
    ///
    /// Prior turns carry only their question and answer text — never their
    /// snippet blocks. Re-sending every turn's snippets would grow the request
    /// quadratically over a long thread; instead the snippets that earlier
    /// answers actually cited are folded into the *current* block by the
    /// caller, so the evidence a follow-up refers to is still present exactly
    /// once.
    static func messages(
        history: [AskTurn],
        question: String,
        sourcesBlock: String,
        maxHistoryTurns: Int = 8
    ) -> [AIChatMessage] {
        var messages: [AIChatMessage] = []
        for turn in history.suffix(maxHistoryTurns) {
            guard let answer = turn.answer else { continue }
            messages.append(AIChatMessage(role: .user, text: turn.question))
            messages.append(AIChatMessage(role: .assistant, text: answer))
        }

        let userText: String
        if sourcesBlock.isEmpty {
            userText = """
            \(question)

            (No new snippets matched this question. Answer from the snippets \
            already discussed, or say that nothing in the meetings covers it.)
            """
        } else {
            userText = """
            \(question)

            SNIPPETS:
            \(sourcesBlock)
            """
        }
        messages.append(AIChatMessage(role: .user, text: userText))
        return messages
    }
}
