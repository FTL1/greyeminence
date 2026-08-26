import XCTest
@testable import Grey_Eminence

/// Pure tests for the conversational Ask: citation numbering (which has to
/// stay stable for the life of a thread), citation parsing/linking (which
/// must never manufacture a link to a snippet that doesn't exist), and prompt
/// assembly (which must not re-send every turn's snippets).
final class AskConversationTests: XCTestCase {

    // MARK: - Fixtures

    private func result(
        id: String,
        text: String = "some transcript text",
        score: Float = 0.5,
        kind: EmbeddingRecord.SourceKind = .transcriptSegment
    ) -> SearchResult {
        SearchResult(
            id: id,
            sourceKind: kind,
            sourceID: UUID(),
            meetingID: UUID(),
            meetingTitle: "Weekly sync",
            meetingDate: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            score: score
        )
    }

    private func conversation() -> AskConversation {
        AskConversation(title: "Test")
    }

    // MARK: - Source numbering

    func testAbsorbNumbersResultsFromOne() {
        var conversation = conversation()
        let numbers = conversation.absorb(
            [result(id: "a"), result(id: "b"), result(id: "c")],
            turnID: UUID()
        )
        XCTAssertEqual(numbers, [1, 2, 3])
        XCTAssertEqual(conversation.sources.map(\.number), [1, 2, 3])
    }

    func testRepeatedSnippetKeepsItsOriginalNumber() {
        var conversation = conversation()
        _ = conversation.absorb([result(id: "a"), result(id: "b")], turnID: UUID())

        // Second turn re-finds "b" and adds a new one. "b" must stay [2] —
        // an earlier answer's [2] has to keep meaning the same snippet.
        let numbers = conversation.absorb([result(id: "b"), result(id: "z")], turnID: UUID())
        XCTAssertEqual(numbers, [2, 3])
        XCTAssertEqual(conversation.sources.count, 3)
    }

    func testRepeatedSnippetKeepsItsBestScore() {
        var conversation = conversation()
        _ = conversation.absorb([result(id: "a", score: 0.2)], turnID: UUID())
        _ = conversation.absorb([result(id: "a", score: 0.9)], turnID: UUID())
        XCTAssertEqual(conversation.source(number: 1)?.result.score, 0.9)

        // A weaker later match must not downgrade it.
        _ = conversation.absorb([result(id: "a", score: 0.1)], turnID: UUID())
        XCTAssertEqual(conversation.source(number: 1)?.result.score, 0.9)
    }

    func testCitedSnippetsSurvivePoolTrimming() {
        var conversation = conversation()
        let firstTurn = UUID()
        _ = conversation.absorb(
            (0..<10).map { result(id: "old\($0)", score: 0.01) },
            turnID: firstTurn
        )
        // Pretend the first answer cited [1].
        var turn = AskTurn(question: "q")
        turn.citedNumbers = [1]
        conversation.turns = [turn]

        // Flood the pool well past its cap with stronger matches.
        _ = conversation.absorb(
            (0..<AskConversation.maxSources + 20).map { result(id: "new\($0)", score: 0.9) },
            turnID: UUID()
        )

        XCTAssertLessThanOrEqual(conversation.sources.count, AskConversation.maxSources)
        XCTAssertNotNil(conversation.source(number: 1), "A cited snippet must never be evicted — its citation would go dead")
    }

    func testRecentlyCitedReadsBackwardsInFirstAppearanceOrder() {
        var conversation = conversation()
        var first = AskTurn(question: "one")
        first.citedNumbers = [4, 1]
        var second = AskTurn(question: "two")
        second.citedNumbers = [1, 7]
        var third = AskTurn(question: "three")
        third.citedNumbers = [9]
        conversation.turns = [first, second, third]

        XCTAssertEqual(conversation.recentlyCitedNumbers(lastTurns: 2), [1, 7, 9])
        XCTAssertEqual(conversation.recentlyCitedNumbers(lastTurns: 3), [4, 1, 7, 9])
    }

    // MARK: - Titles

    func testTitleClipsAtAWordBoundary() {
        let title = AskConversation.title(
            fromFirstQuestion: "What did we decide about the document service migration timeline and rollout"
        )
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(title.count, 53)
        XCTAssertFalse(title.dropLast().hasSuffix(" "), "Should trim the space before the ellipsis")
    }

    func testShortQuestionBecomesTheTitleVerbatim() {
        XCTAssertEqual(AskConversation.title(fromFirstQuestion: "Who owns auth?"), "Who owns auth?")
    }

    func testTitleFlattensNewlines() {
        XCTAssertEqual(AskConversation.title(fromFirstQuestion: "Line one\nline two"), "Line one line two")
    }

    // MARK: - Citation parsing

    func testCitedNumbersAreFirstAppearanceOrderWithoutDuplicates() {
        let answer = "You agreed to ship it [3]. Erin pushed back [1, 3] and then relented [7]."
        XCTAssertEqual(AskCitations.cited(in: answer), [3, 1, 7])
    }

    func testProseBracketsAreNotCitations() {
        XCTAssertEqual(AskCitations.cited(in: "He said [inaudible] and [see notes]."), [])
    }

    func testLinkifyRewritesKnownCitations() {
        let linked = AskCitations.linkify("Shipped on Friday [2].", known: [1, 2, 3])
        XCTAssertTrue(linked.contains("[2](\(AskCitations.scheme)://source/2)"), "got: \(linked)")
    }

    func testLinkifyLeavesUnknownCitationsAsPlainText() {
        // A model that cites a snippet it wasn't given must not produce a link
        // to nothing.
        let linked = AskCitations.linkify("As discussed [99].", known: [1, 2])
        XCTAssertEqual(linked, "As discussed [99].")
    }

    func testLinkifyExpandsGroupedCitationsIndividually() {
        let linked = AskCitations.linkify("Both agreed [1, 2].", known: [1, 2])
        XCTAssertTrue(linked.contains("[1](\(AskCitations.scheme)://source/1)"), "got: \(linked)")
        XCTAssertTrue(linked.contains("[2](\(AskCitations.scheme)://source/2)"), "got: \(linked)")
    }

    func testLinkifyHandlesMultipleCitationsWithoutCorruptingRanges() {
        // Replacements run back-to-front; a forward pass would shift every
        // later range and mangle the text.
        let linked = AskCitations.linkify("One [1] two [2] three [3].", known: [1, 2, 3])
        for number in 1...3 {
            XCTAssertTrue(
                linked.contains("[\(number)](\(AskCitations.scheme)://source/\(number))"),
                "citation \(number) missing from: \(linked)"
            )
        }
    }

    func testCitationURLRoundTrips() throws {
        let url = try XCTUnwrap(AskCitations.url(forNumber: 12))
        XCTAssertEqual(AskCitations.number(fromURL: url), 12)
    }

    func testForeignURLIsNotTreatedAsACitation() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/source/4"))
        XCTAssertNil(AskCitations.number(fromURL: url))
    }

    // MARK: - Prompt assembly

    private func sources(_ numbers: [Int]) -> [AskSource] {
        numbers.map { number in
            AskSource(
                number: number,
                result: CodableSearchResult(result(id: "s\(number)", text: "snippet \(number) body")),
                firstSeenTurn: UUID()
            )
        }
    }

    func testSourcesBlockNumbersMatchTheSourceNumbers() {
        let block = AskPromptBuilder.sourcesBlock(sources([4, 9]))
        XCTAssertTrue(block.contains("[4] transcript — Weekly sync"), "got: \(block)")
        XCTAssertTrue(block.contains("[9] transcript — Weekly sync"), "got: \(block)")
        XCTAssertTrue(block.contains("snippet 4 body"))
    }

    func testSourcesBlockIncludesLeadInAheadOfTheSnippet() {
        let source = sources([1])[0]
        let block = AskPromptBuilder.sourcesBlock([source], leadIns: [source.id: "Me: setting it up"])
        let leadIndex = try? XCTUnwrap(block.range(of: "Me: setting it up"))
        let bodyIndex = try? XCTUnwrap(block.range(of: "snippet 1 body"))
        XCTAssertNotNil(leadIndex)
        XCTAssertNotNil(bodyIndex)
        if let leadIndex, let bodyIndex {
            XCTAssertLessThan(leadIndex.lowerBound, bodyIndex.lowerBound, "Lead-in must precede the snippet")
        }
    }

    func testMessagesAlternateAndEndOnTheUser() {
        var answered = AskTurn(question: "first question")
        answered.answer = "first answer"
        let messages = AskPromptBuilder.messages(
            history: [answered],
            question: "follow up",
            sourcesBlock: "[1] transcript — x"
        )
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(messages.last?.role, .user)
        XCTAssertTrue(messages.last?.text.contains("follow up") == true)
    }

    func testHistoryCarriesQuestionsAndAnswersButNotTheirSnippets() {
        var answered = AskTurn(question: "first question")
        answered.answer = "first answer"
        let messages = AskPromptBuilder.messages(
            history: [answered],
            question: "follow up",
            sourcesBlock: "[9] transcript — new snippet"
        )
        // Only the current turn carries a SNIPPETS block; re-sending each
        // turn's snippets would grow the request quadratically.
        let withSnippets = messages.filter { $0.text.contains("SNIPPETS:") }
        XCTAssertEqual(withSnippets.count, 1)
        XCTAssertEqual(withSnippets.first?.role, .user)
    }

    func testUnansweredTurnsAreDroppedFromHistory() {
        // A failed or cancelled turn has no assistant reply; leaving the user
        // half in would break the required user/assistant alternation.
        let failed = AskTurn(question: "died mid-flight")
        var answered = AskTurn(question: "worked")
        answered.answer = "an answer"
        let messages = AskPromptBuilder.messages(
            history: [failed, answered],
            question: "next",
            sourcesBlock: "[1] x"
        )
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user])
        XCTAssertFalse(messages.contains { $0.text.contains("died mid-flight") })
    }

    func testHistoryIsTrimmedToTheMostRecentTurns() {
        let history: [AskTurn] = (0..<10).map { index in
            var turn = AskTurn(question: "question \(index)")
            turn.answer = "answer \(index)"
            return turn
        }
        let messages = AskPromptBuilder.messages(
            history: history,
            question: "latest",
            sourcesBlock: "[1] x",
            maxHistoryTurns: 3
        )
        XCTAssertEqual(messages.count, 3 * 2 + 1)
        XCTAssertFalse(messages.contains { $0.text == "question 6" })
        XCTAssertTrue(messages.contains { $0.text == "question 7" })
    }

    func testEmptySourcesBlockStillAsksTheQuestion() {
        let messages = AskPromptBuilder.messages(history: [], question: "anything?", sourcesBlock: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].text.contains("anything?"))
        XCTAssertFalse(messages[0].text.contains("SNIPPETS:"))
    }

    // MARK: - Query condensing

    func testCondensedQueryIsTrimmedOfQuotes() {
        XCTAssertEqual(
            AskPromptBuilder.sanitizeCondensed("\"document service rollout\"", fallback: "raw"),
            "document service rollout"
        )
    }

    func testRamblingCondenserOutputFallsBackToTheRawQuestion() {
        let rambling = "Here is the query you asked for.\n\nIt resolves the pronoun to Erin and searches for the auth migration."
        XCTAssertEqual(AskPromptBuilder.sanitizeCondensed(rambling, fallback: "what did she say?"), "what did she say?")
    }

    func testEmptyCondenserOutputFallsBackToTheRawQuestion() {
        XCTAssertEqual(AskPromptBuilder.sanitizeCondensed("   ", fallback: "original"), "original")
    }

    func testOverlongCondenserOutputFallsBackToTheRawQuestion() {
        XCTAssertEqual(
            AskPromptBuilder.sanitizeCondensed(String(repeating: "word ", count: 100), fallback: "original"),
            "original"
        )
    }

    func testCondensePromptCarriesTheRecentExchange() {
        var turn = AskTurn(question: "Who owns the document service?")
        turn.answer = "Erin owns it."
        let prompt = AskPromptBuilder.condensePrompt(history: [turn], question: "what did she say about timelines?")
        XCTAssertTrue(prompt.contains("Who owns the document service?"))
        XCTAssertTrue(prompt.contains("Erin owns it."))
        XCTAssertTrue(prompt.contains("what did she say about timelines?"))
    }
}

/// The person scope must include material where somebody is *named*, not just
/// meetings they sat in. This is the shape of the regression that lost a real
/// answer: the snippet was in a meeting Stephen Smith did not attend, and it
/// was someone else relaying what he had said.
final class AskPersonScopeTests: XCTestCase {
    private let attended = UUID()
    private let notAttended = UUID()

    private func scope() -> SemanticSearchService.PersonScope {
        .init(meetingIDs: [attended], mentionNames: ["stephen smith", "stephen", "smith"])
    }

    private func admits(meetingID: UUID, text: String) -> Bool {
        SemanticSearchService.PersonScope.admitsForTesting(scope(), meetingID: meetingID, text: text)
    }

    func testMeetingTheyAttendedIsAdmitted() {
        XCTAssertTrue(admits(meetingID: attended, text: "nothing about anyone in particular"))
    }

    func testMentionInAMeetingTheyMissedIsAdmitted() {
        XCTAssertTrue(admits(
            meetingID: notAttended,
            text: "Me: And so what Stephen's fear is, well, it's not even a fear. He just said there's no way."
        ))
    }

    func testUnrelatedMaterialIsExcluded() {
        XCTAssertFalse(admits(meetingID: notAttended, text: "Me: the ingestion pipeline throughput looks fine"))
    }

    func testMentionMatchingRespectsWordBoundaries() {
        // A short surname must not match inside an ordinary word — this is why
        // parts shorter than four characters never become mention terms.
        let narrow = SemanticSearchService.PersonScope(meetingIDs: [], mentionNames: ["gene huh", "gene"])
        XCTAssertFalse(
            SemanticSearchService.PersonScope.admitsForTesting(narrow, meetingID: notAttended, text: "we generate the report nightly"),
            "\"gene\" must not match inside \"generate\""
        )
        XCTAssertTrue(
            SemanticSearchService.PersonScope.admitsForTesting(narrow, meetingID: notAttended, text: "Gene walked through the intake flow")
        )
    }
}
