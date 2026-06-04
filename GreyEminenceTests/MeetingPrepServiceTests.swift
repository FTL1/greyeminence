import XCTest
@testable import Grey_Eminence

/// Pure, offline tests for the prep-scoping helpers — the "last N meetings"
/// recency cut and the provenance summary wording. No SwiftData involved.
final class MeetingPrepServiceTests: XCTestCase {

    /// Fixed reference so the test is deterministic (no `Date.now`).
    private func date(_ daysAgo: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000)
            .addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    }

    // MARK: - Recency cut (the "61 days ago" fix)

    func testRecentMeetingIDsKeepsNewestN() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let meetings: [(id: UUID, date: Date)] = [
            (a, date(61)),   // oldest — dropped
            (b, date(7)),    // newest
            (c, date(30)),
            (d, date(14)),
        ]
        // Newest first, capped at 2 → [b (7d), d (14d)]; the 61-day item is gone.
        XCTAssertEqual(MeetingPrepService.recentMeetingIDs(from: meetings, limit: 2), [b, d])
    }

    func testRecentMeetingIDsHandlesFewerThanLimit() {
        let a = UUID()
        XCTAssertEqual(MeetingPrepService.recentMeetingIDs(from: [(a, date(3))], limit: 2), [a])
    }

    func testRecentMeetingIDsEmpty() {
        XCTAssertEqual(MeetingPrepService.recentMeetingIDs(from: [], limit: 2), [])
    }

    // MARK: - Provenance summary

    func testSummarySeriesWording() {
        XCTAssertEqual(
            MeetingPrepService.summary(count: 1, isSeries: true, seriesTitle: "OLP Team Sync", attendeeNames: []),
            "From your last OLP Team Sync"
        )
        XCTAssertEqual(
            MeetingPrepService.summary(count: 2, isSeries: true, seriesTitle: "OLP Team Sync", attendeeNames: ["Erin"]),
            "From your last 2 OLP Team Sync meetings"
        )
    }

    func testSummaryAttendeeWording() {
        XCTAssertEqual(
            MeetingPrepService.summary(count: 1, isSeries: false, seriesTitle: nil, attendeeNames: ["Erin", "Razia"]),
            "From your last meeting with Erin, Razia"
        )
        // Names capped at 2 even when more attendees matched.
        XCTAssertEqual(
            MeetingPrepService.summary(count: 2, isSeries: false, seriesTitle: nil, attendeeNames: ["Erin", "Razia", "Kate"]),
            "From your last 2 meetings with Erin, Razia"
        )
    }

    func testSummaryEmptyWhenNoHistory() {
        XCTAssertEqual(
            MeetingPrepService.summary(count: 0, isSeries: false, seriesTitle: nil, attendeeNames: ["Erin"]),
            ""
        )
    }

    // MARK: - Order-preserving dedupe

    func testDedupePreservingOrder() {
        XCTAssertEqual(
            MeetingPrepService.dedupePreservingOrder(["a", "b", "a", "c", "b"]),
            ["a", "b", "c"]
        )
    }
}
