import XCTest
@testable import Grey_Eminence

final class TaskQueryParserTests: XCTestCase {
    func testPastDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = TaskQueryParser.parse("past 30 days", now: now)
        XCTAssertNotNil(parsed?.since)
        let days = Calendar.current.dateComponents([.day], from: parsed!.since!, to: now).day
        XCTAssertEqual(days, 30)
    }

    func testDroppedLastMonthImpliesStalled() {
        let parsed = TaskQueryParser.parse("dropped last month")
        XCTAssertEqual(parsed?.onlyStalled, true)
        XCTAssertNotNil(parsed?.since)
    }

    func testMineHint() {
        XCTAssertEqual(TaskQueryParser.parse("my action items past 7 days")?.people, .mine)
    }

    func testSeriesNameFallback() {
        XCTAssertEqual(TaskQueryParser.parse("Weekly Standup")?.meetingHint, "Weekly Standup")
    }

    func testEmptyIsNil() {
        XCTAssertNil(TaskQueryParser.parse("   "))
    }
}
