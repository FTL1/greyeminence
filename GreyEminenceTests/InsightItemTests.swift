import XCTest
@testable import Grey_Eminence

final class InsightItemTests: XCTestCase {
    func testReorderMovesFollowUps() {
        var questions = ["A", "B", "C"]
        InsightReorder.move(&questions, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(questions, ["C", "A", "B"])
    }

    func testSummaryRoundTripAfterReorder() throws {
        let sections = [
            SummarySection(title: "One", intro: nil, points: [SummaryPoint(label: "A", detail: "a")]),
            SummarySection(title: "Two", intro: "hi", points: []),
        ]
        var next = sections
        InsightReorder.move(&next, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(next.map(\.title), ["Two", "One"])
        let encoded = try XCTUnwrap(SummarySection.encode(next))
        let parsed = try XCTUnwrap(SummarySection.parse(encoded))
        XCTAssertEqual(parsed.map(\.title), ["Two", "One"])
    }
}
