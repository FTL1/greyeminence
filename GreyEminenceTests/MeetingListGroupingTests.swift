import XCTest
import SwiftData
@testable import Grey_Eminence

/// Month sections are ordered by date, not by header text. Sorting the labels
/// as strings put "June 2026" above "July 2026" ('n' > 'l'), which pushed a
/// whole month of meetings below an older section where they read as missing.
@MainActor
final class MeetingListGroupingTests: XCTestCase {

    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    /// Fixed reference point so bucketing never depends on the wall clock.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @discardableResult
    private func makeMeeting(_ date: Date, title: String = "Meeting") -> Meeting {
        let meeting = Meeting(title: title)
        meeting.date = date
        context.insert(meeting)
        return meeting
    }

    private func sections(_ meetings: [Meeting], now: Date) -> [String] {
        MeetingListView.groupSections(for: meetings, now: now, calendar: calendar)
            .map(\.0)
    }

    func testJulySortsAboveJune() {
        let now = date(2026, 8, 3)
        let meetings = [makeMeeting(date(2026, 6, 16)), makeMeeting(date(2026, 7, 17))]

        XCTAssertEqual(sections(meetings, now: now), ["July 2026", "June 2026"])
    }

    /// The same defect in the other direction: "January" beats "February"
    /// alphabetically, so a string sort inverted them too.
    func testFebruarySortsAboveJanuary() {
        let now = date(2026, 4, 10)
        let meetings = [makeMeeting(date(2026, 1, 5)), makeMeeting(date(2026, 2, 5))]

        XCTAssertEqual(sections(meetings, now: now), ["February 2026", "January 2026"])
    }

    func testRelativeSectionsPrecedeMonthSections() {
        let now = date(2026, 8, 3)
        let meetings = [
            makeMeeting(date(2026, 6, 16)),
            makeMeeting(date(2026, 7, 17)),
            makeMeeting(date(2026, 8, 3)),
            makeMeeting(date(2026, 8, 2)),
        ]

        XCTAssertEqual(
            sections(meetings, now: now),
            ["Today", "Yesterday", "July 2026", "June 2026"]
        )
    }

    func testMonthSectionsOrderAcrossYearBoundary() {
        let now = date(2026, 3, 1)
        let meetings = [makeMeeting(date(2025, 12, 10)), makeMeeting(date(2026, 1, 10))]

        XCTAssertEqual(sections(meetings, now: now), ["January 2026", "December 2025"])
    }

    func testMeetingsStayWithinTheirSection() {
        let now = date(2026, 8, 3)
        let june = makeMeeting(date(2026, 6, 16), title: "June call")
        let july = makeMeeting(date(2026, 7, 17), title: "July call")

        let grouped = MeetingListView.groupSections(
            for: [june, july], now: now, calendar: calendar
        )

        XCTAssertEqual(grouped.first?.1.map(\.title), ["July call"])
        XCTAssertEqual(grouped.last?.1.map(\.title), ["June call"])
    }
}
