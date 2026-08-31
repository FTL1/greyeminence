import XCTest
import SwiftData
@testable import Grey_Eminence

@MainActor
final class MeetingReanalysisTests: XCTestCase {
    func testNormalizeKeyCollapsesWhitespaceAndStripsTrailingPunctuation() {
        XCTAssertEqual(MeetingReanalysis.normalizeKey("  Hello,  World! "), "hello, world")
        XCTAssertEqual(MeetingReanalysis.normalizeKey("Follow-up?"), "follow-up")
        XCTAssertEqual(MeetingReanalysis.normalizeKey("same   KEY."), "same key")
    }

    func testQueueFailureKeepsMeetingIdentityAndMessage() {
        let meetingID = UUID()
        let failure = MeetingReanalysisQueue.Failure(
            id: UUID(),
            meetingID: meetingID,
            title: "Grey Conseil - vendor sync up",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            message: "The request timed out."
        )
        XCTAssertEqual(failure.meetingID, meetingID)
        XCTAssertTrue(failure.message.localizedCaseInsensitiveContains("timed out"))
        XCTAssertEqual(
            [failure].compactMap(\.meetingID),
            [meetingID]
        )
    }

    func testAnalysisTitleHintPrefersCalendarEventName() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Stored name")
        container.mainContext.insert(meeting)
        XCTAssertEqual(meeting.analysisTitleHint, "Stored name")

        meeting.calendarEventTitle = "North Campus Engineering Scope Review"
        XCTAssertEqual(meeting.analysisTitleHint, "North Campus Engineering Scope Review")

        meeting.calendarEventTitle = "   "
        XCTAssertEqual(meeting.analysisTitleHint, "Stored name")
    }

    func testRenameDisplayTitleTrimsAndRejectsEmpty() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Standup")
        container.mainContext.insert(meeting)
        XCTAssertTrue(meeting.renameDisplayTitle("  Q2 budget  "))
        XCTAssertEqual(meeting.title, "Q2 budget")
        XCTAssertFalse(meeting.renameDisplayTitle("   "))
        XCTAssertEqual(meeting.title, "Q2 budget")
        XCTAssertFalse(meeting.renameDisplayTitle("Q2 budget"))
    }

    func testApplyGeneratedTitleDoesNotOverwriteUserRename() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Meeting 8/27/26")
        container.mainContext.insert(meeting)
        XCTAssertTrue(Meeting.isAutomaticTitle(meeting.title))
        meeting.applyGeneratedTitle("Align prospect docs with Jordan")
        XCTAssertEqual(meeting.title, "Align prospect docs with Jordan")
        XCTAssertTrue(meeting.renameDisplayTitle("Q2 budget"))
        meeting.applyGeneratedTitle("A different AI title")
        XCTAssertEqual(meeting.generatedTitle, "A different AI title")
        XCTAssertEqual(meeting.title, "Q2 budget")
    }

    func testApplyGeneratedTitleDoesNotOverwriteCalendarLinkedTitle() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "North Campus Engineering Scope Review")
        meeting.calendarEventID = "evt-1"
        meeting.calendarEventTitle = "North Campus Engineering Scope Review"
        container.mainContext.insert(meeting)

        meeting.applyGeneratedTitle("Align prospect docs with Jordan")
        XCTAssertEqual(meeting.generatedTitle, "Align prospect docs with Jordan")
        XCTAssertEqual(meeting.title, "North Campus Engineering Scope Review")
    }

    func testActionSnapshotRoundTrip() {
        let items = [
            ParsedActionItem(text: "Fix the ROM", assignee: "Me", sourceQuote: nil),
            ParsedActionItem(text: "Send drawings", assignee: "Jordan", sourceQuote: nil),
        ]
        let json = InsightRevision.encodeActions(items)
        let decoded = InsightRevision.decodeActions(json)
        XCTAssertEqual(decoded.map(\.text), ["Fix the ROM", "Send drawings"])
        XCTAssertEqual(decoded.map(\.assignee), ["Me", "Jordan"])
    }

    func testCanRevertRequiresTwoInsights() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Call")
        container.mainContext.insert(meeting)
        XCTAssertFalse(InsightRevision.canRevert(meeting))
        let a = MeetingInsight(summary: "one")
        a.meeting = meeting
        meeting.insights.append(a)
        container.mainContext.insert(a)
        XCTAssertFalse(InsightRevision.canRevert(meeting))
        let b = MeetingInsight(summary: "two")
        b.meeting = meeting
        meeting.insights.append(b)
        container.mainContext.insert(b)
        XCTAssertTrue(InsightRevision.canRevert(meeting))
    }
}
