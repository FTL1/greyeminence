import XCTest
import SwiftData
@testable import Grey_Eminence

/// Unlinking a calendar event prunes the attendee list: the event was the
/// wrong one, so the attendees it contributed are presumed wrong too.
@MainActor
final class MeetingUnlinkTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeLinkedMeeting(in context: ModelContext, attendees: [Contact]) -> Meeting {
        let meeting = Meeting(title: "Standup")
        meeting.calendarEventID = "event-1"
        meeting.calendarEventTitle = "Standup"
        context.insert(meeting)
        for contact in attendees {
            context.insert(contact)
            meeting.attendees.append(contact)
        }
        return meeting
    }

    func testUnlinkKeepsOnlyMe() throws {
        let context = try makeContext()
        let me = Contact(name: "Me Myself")
        let other = Contact(name: "Wrong Person")
        let meeting = makeLinkedMeeting(in: context, attendees: [me, other])

        meeting.unlinkCalendarEvent(keepingAttendeeID: me.id)

        XCTAssertEqual(meeting.attendees.map(\.id), [me.id])
        XCTAssertNil(meeting.calendarEventID)
        XCTAssertNil(meeting.calendarEventTitle)
    }

    func testUnlinkWithNoMyProfileRemovesEveryone() throws {
        let context = try makeContext()
        let a = Contact(name: "Person A")
        let b = Contact(name: "Person B")
        let meeting = makeLinkedMeeting(in: context, attendees: [a, b])

        meeting.unlinkCalendarEvent(keepingAttendeeID: nil)

        XCTAssertTrue(meeting.attendees.isEmpty)
    }

    func testUnlinkRestoresGeneratedTitleAndPrunes() throws {
        let context = try makeContext()
        let me = Contact(name: "Me Myself")
        let other = Contact(name: "Wrong Person")
        let meeting = makeLinkedMeeting(in: context, attendees: [me, other])
        meeting.title = "Standup"           // still event-derived
        meeting.generatedTitle = "Roadmap sync"

        meeting.unlinkCalendarEvent(keepingAttendeeID: me.id)

        XCTAssertEqual(meeting.title, "Roadmap sync")
        XCTAssertEqual(meeting.attendees.map(\.id), [me.id])
    }
}
