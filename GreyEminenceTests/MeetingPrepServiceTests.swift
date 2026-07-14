import XCTest
@testable import Grey_Eminence

/// Pure, offline tests for the prep helpers — provenance summary wording,
/// assignee cleaning, and order-preserving dedupe. No SwiftData involved.
final class MeetingPrepServiceTests: XCTestCase {

    // MARK: - History summary

    func testHistorySummarySingleOccurrence() {
        // No date → stable, no locale-dependent string to assert.
        XCTAssertEqual(
            MeetingPrepView.historySummary(count: 1, mostRecent: nil),
            "From the last time you recorded this meeting"
        )
    }

    func testHistorySummaryMultipleOccurrences() {
        XCTAssertEqual(
            MeetingPrepView.historySummary(count: 2, mostRecent: nil),
            "From your last 2 recordings of this meeting"
        )
        XCTAssertEqual(
            MeetingPrepView.historySummary(count: 3, mostRecent: nil),
            "From your last 3 recordings of this meeting"
        )
    }

    func testHistorySummarySingleOccurrenceIncludesDateWhenPresent() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = MeetingPrepView.historySummary(count: 1, mostRecent: date)
        XCTAssertTrue(summary.hasPrefix("From the last time you recorded this meeting · "))
        XCTAssertTrue(summary.count > "From the last time you recorded this meeting · ".count)
    }

    // MARK: - Assignee cleaning (the "Speaker 2" leak)

    func testCleanAssigneeStripsDiarizationPlaceholders() {
        XCTAssertNil(MeetingPrepService.cleanAssignee("Speaker 2"))
        XCTAssertNil(MeetingPrepService.cleanAssignee("speaker 10"))
        XCTAssertNil(MeetingPrepService.cleanAssignee("Unknown"))
        XCTAssertNil(MeetingPrepService.cleanAssignee("Me"))
        XCTAssertNil(MeetingPrepService.cleanAssignee("   "))
        XCTAssertNil(MeetingPrepService.cleanAssignee(nil))
    }

    func testCleanAssigneeKeepsRealNames() {
        XCTAssertEqual(MeetingPrepService.cleanAssignee("Haley"), "Haley")
        XCTAssertEqual(MeetingPrepService.cleanAssignee("  Stephen Smith "), "Stephen Smith")
        // "Speaker" as part of a real title shouldn't be stripped (only the
        // "Speaker N" diarization prefix is).
        XCTAssertEqual(MeetingPrepService.cleanAssignee("Speakerphone Vendor"), "Speakerphone Vendor")
    }

    // MARK: - Order-preserving dedupe

    func testDedupePreservingOrder() {
        XCTAssertEqual(
            MeetingPrepService.dedupePreservingOrder(["a", "b", "a", "c", "b"]),
            ["a", "b", "c"]
        )
    }
}
