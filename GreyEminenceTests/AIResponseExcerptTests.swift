import XCTest
@testable import Grey_Eminence

/// A response that reaches the parse-failure log has already survived the
/// decoder's three truncation-salvage passes, so it is malformed at a boundary
/// rather than simply cut off — and the boundary is usually the end. Logging
/// only the head records the part that was fine.
final class AIResponseExcerptTests: XCTestCase {

    func testShortResponseIsLoggedWhole() {
        let response = #"{"title":"short"}"#
        let excerpt = AIResponseDecoder.failureExcerpt(response)

        XCTAssertTrue(excerpt.contains(response))
        XCTAssertFalse(excerpt.contains("omitted"))
        XCTAssertTrue(excerpt.hasPrefix("\(response.count) chars:"))
    }

    func testLongResponseKeepsBothEnds() {
        let head = String(repeating: "H", count: 900)
        let tail = String(repeating: "T", count: 900)
        let response = head + tail

        let excerpt = AIResponseDecoder.failureExcerpt(response, headLimit: 100, tailLimit: 100)

        XCTAssertTrue(excerpt.contains(String(repeating: "H", count: 100)))
        XCTAssertTrue(excerpt.contains(String(repeating: "T", count: 100)))
        XCTAssertTrue(excerpt.contains("[1600 chars omitted]"))
    }

    /// The whole point: whatever made the JSON invalid is often the last thing
    /// in the payload — trailing prose, a stray fence, an unterminated string.
    func testTrailingGarbageSurvivesTruncation() {
        let response = #"{"title":"x","summary":["# + String(repeating: "a", count: 5_000) + #"]} Sorry, I can't complete that."#
        let excerpt = AIResponseDecoder.failureExcerpt(response)

        XCTAssertTrue(
            excerpt.contains("Sorry, I can't complete that."),
            "the trailing text that broke parsing must appear in the log"
        )
    }

    func testExcerptReportsFullLength() {
        let response = String(repeating: "x", count: 4_321)
        XCTAssertTrue(AIResponseDecoder.failureExcerpt(response).hasPrefix("4321 chars:"))
    }

    func testBoundaryLengthIsNotTruncated() {
        // Exactly head + tail — nothing to omit, so log it whole.
        let response = String(repeating: "x", count: 200)
        let excerpt = AIResponseDecoder.failureExcerpt(response, headLimit: 100, tailLimit: 100)

        XCTAssertFalse(excerpt.contains("omitted"))
    }
}
