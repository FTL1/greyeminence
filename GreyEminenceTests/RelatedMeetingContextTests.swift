import XCTest
@testable import Grey_Eminence

/// Pure tests for the blind-spot grounding block: snippet formatting with
/// per-meeting diversity caps, and how the prompt template embeds it.
final class RelatedMeetingContextTests: XCTestCase {

    private func result(meetingID: UUID, title: String, text: String) -> SearchResult {
        SearchResult(
            id: UUID().uuidString,
            sourceKind: .transcriptSegment,
            sourceID: UUID(),
            meetingID: meetingID,
            meetingTitle: title,
            meetingDate: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            score: 1.0
        )
    }

    func testFormatReturnsNilForEmptyOrBlankResults() {
        XCTAssertNil(RelatedMeetingContext.format(results: []))
        XCTAssertNil(RelatedMeetingContext.format(results: [
            result(meetingID: UUID(), title: "Sync", text: "   ")
        ]))
    }

    func testFormatCapsSnippetsPerMeeting() {
        let dominant = UUID()
        let other = UUID()
        var results = (1...6).map {
            result(meetingID: dominant, title: "Dominant", text: "dominant snippet \($0)")
        }
        results.append(result(meetingID: other, title: "Other", text: "other snippet"))

        let block = RelatedMeetingContext.format(results: results)!
        let lines = block.split(separator: "\n")

        XCTAssertEqual(lines.filter { $0.contains("dominant snippet") }.count, RelatedMeetingContext.perMeetingCap)
        XCTAssertTrue(block.contains("other snippet"))
    }

    func testFormatRespectsTotalSnippetLimit() {
        let results = (1...20).map {
            result(meetingID: UUID(), title: "M\($0)", text: "snippet \($0)")
        }
        let block = RelatedMeetingContext.format(results: results)!
        XCTAssertEqual(block.split(separator: "\n").count, RelatedMeetingContext.snippetLimit)
    }

    func testRelatedContextBlockEmptyWhenNoSnippets() {
        XCTAssertEqual(AIPromptTemplates.relatedContextBlock(nil), "")
        XCTAssertEqual(AIPromptTemplates.relatedContextBlock(""), "")
    }

    func testFinalCleanupPromptEmbedsRelatedContext() {
        let prompt = AIPromptTemplates.finalCleanupPrompt(
            fullTranscript: "transcript body",
            currentSummary: "[]",
            currentActionItems: [],
            currentFollowUps: [],
            currentTopics: [],
            relatedContext: "- [Roadmap Sync — Nov 14, 2023] capacity planning discussion"
        )
        XCTAssertTrue(prompt.contains("RELATED DISCUSSIONS FROM OTHER MEETINGS"))
        XCTAssertTrue(prompt.contains("capacity planning discussion"))
        XCTAssertFalse(prompt.contains("{{relatedContext}}"))
    }

    func testFinalCleanupPromptOmitsBlockWithoutRelatedContext() {
        let prompt = AIPromptTemplates.finalCleanupPrompt(
            fullTranscript: "transcript body",
            currentSummary: "[]",
            currentActionItems: [],
            currentFollowUps: [],
            currentTopics: []
        )
        XCTAssertFalse(prompt.contains("RELATED DISCUSSIONS FROM OTHER MEETINGS"))
        XCTAssertFalse(prompt.contains("{{relatedContext}}"))
    }
}
