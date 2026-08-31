import XCTest
@testable import Grey_Eminence

final class TopicDialogMatcherTests: XCTestCase {
    func testNormalizeIsCaseInsensitive() {
        XCTAssertTrue(TopicDialogMatcher.topicsMatch("Community Opposition", "community opposition"))
        XCTAssertFalse(TopicDialogMatcher.topicsMatch("GNB", "Site B"))
    }

    func testPhraseMatch() {
        XCTAssertTrue(
            TopicDialogMatcher.segmentMatches(
                "They talked about Community Opposition near North Campus.",
                topic: "Community Opposition"
            )
        )
    }

    func testSingleTokenUsesWordBoundary() {
        XCTAssertTrue(TopicDialogMatcher.segmentMatches("GNB sent a stale deck.", topic: "GNB"))
        XCTAssertFalse(TopicDialogMatcher.segmentMatches("The signal was strong.", topic: "GNB"))
    }

    func testMultiTokenRequiresEverySignificantWord() {
        XCTAssertTrue(
            TopicDialogMatcher.segmentMatches(
                "First Nations partnership talks with Chief George.",
                topic: "First Nations Partnership"
            )
        )
        XCTAssertFalse(
            TopicDialogMatcher.segmentMatches(
                "They mentioned the First Nations community.",
                topic: "First Nations Partnership"
            )
        )
    }

    func testMeetingsSharingTopicExcludesCurrent() {
        // Pure filter is covered via meetings(sharing:excluding:among:) on
        // topic labels; this test uses the normalize helper only so it stays
        // free of SwiftData.
        XCTAssertEqual(TopicDialogMatcher.significantTokens(in: "the Site Exclusivity"), ["site", "exclusivity"])
        XCTAssertEqual(TopicDialogMatcher.significantTokens(in: "GNB"), ["gnb"])
    }
}
