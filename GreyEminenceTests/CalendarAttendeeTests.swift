import XCTest
import SwiftData
@testable import Grey_Eminence

/// Attendee identity resolution and contact auto-creation on calendar link:
/// unmatched invitees become Contact records (we have their full name and
/// email from the invite), while existing contacts are matched — email first.
@MainActor
final class CalendarAttendeeTests: XCTestCase {

    // MARK: - EventAttendee.resolve

    func testResolveKeepsNameAndNormalizesEmail() {
        let attendee = EventAttendee.resolve(name: "Sam Lee", email: " Sam@Org.com ")
        XCTAssertEqual(attendee?.name, "Sam Lee")
        XCTAssertEqual(attendee?.email, "sam@org.com")
    }

    func testResolveDerivesReadableNameFromEmailOnly() {
        let attendee = EventAttendee.resolve(name: nil, email: "sam.lee@org.com")
        XCTAssertEqual(attendee?.name, "Sam Lee")
        XCTAssertEqual(attendee?.email, "sam.lee@org.com")
    }

    func testResolveHandlesAddressInNameSlot() {
        let attendee = EventAttendee.resolve(name: "jane_doe@org.com", email: nil)
        XCTAssertEqual(attendee?.name, "Jane Doe")
        XCTAssertEqual(attendee?.email, "jane_doe@org.com")
    }

    func testResolveReturnsNilWithNoUsableIdentity() {
        XCTAssertNil(EventAttendee.resolve(name: "  ", email: nil))
        XCTAssertNil(EventAttendee.resolve(name: nil, email: "not-an-email"))
    }

    // MARK: - linkEvent contact creation

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Meeting.self, Contact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeEvent(attendees: [EventAttendee]) -> CalendarEvent {
        CalendarEvent(
            id: "evt-1",
            linkIdentifier: "evt-1",
            title: "Planning",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            attendees: attendees,
            isRecurring: false,
            source: .eventKit
        )
    }

    func testLinkCreatesContactsForUnknownAttendees() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Planning")
        context.insert(meeting)

        let service = CalendarService()
        service.linkEvent(
            makeEvent(attendees: [
                EventAttendee(name: "Sam Lee", email: "sam@org.com"),
                EventAttendee(name: "Sam Lee", email: "sam@org.com"),   // duplicate invite entry
            ]),
            to: meeting,
            in: context,
            setTitle: false
        )

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(contacts.count, 1)                       // deduped within the event
        XCTAssertEqual(contacts.first?.name, "Sam Lee")
        XCTAssertEqual(contacts.first?.email, "sam@org.com")
        XCTAssertEqual(meeting.attendees.map(\.name), ["Sam Lee"])
    }

    func testLinkMatchesExistingContactByEmailInsteadOfCreating() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Planning")
        context.insert(meeting)
        // Same person, different display name on the invite — email wins.
        let existing = Contact(name: "Samantha Lee", email: "sam@org.com")
        context.insert(existing)

        let service = CalendarService()
        service.linkEvent(
            makeEvent(attendees: [EventAttendee(name: "Sam Lee", email: "sam@org.com")]),
            to: meeting,
            in: context,
            setTitle: false
        )

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(contacts.count, 1)                       // no duplicate created
        XCTAssertEqual(meeting.attendees.map(\.id), [existing.id])
    }

    func testLinkDoesNotResurrectInactiveContact() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Planning")
        context.insert(meeting)
        // This person left the company — marked inactive (isArchived).
        let former = Contact(name: "Sam Lee", email: "sam@org.com")
        former.isArchived = true
        context.insert(former)

        let service = CalendarService()
        service.linkEvent(
            makeEvent(attendees: [EventAttendee(name: "Sam Lee", email: "sam@org.com")]),
            to: meeting,
            in: context,
            setTitle: false
        )

        // Recognized (so no duplicate created) but NOT re-added to the meeting.
        let contacts = try context.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(contacts.count, 1)
        XCTAssertTrue(meeting.attendees.isEmpty)
    }

    func testLinkNeverCreatesContactForCurrentUser() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Planning")
        context.insert(meeting)

        let service = CalendarService()
        service.linkEvent(
            makeEvent(attendees: [
                EventAttendee(name: "Alex Morgan", email: "alex@org.com", isCurrentUser: true),
                EventAttendee(name: "Sam Lee", email: "sam@org.com"),
            ]),
            to: meeting,
            in: context,
            setTitle: false
        )

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(contacts.map(\.name), ["Sam Lee"])       // no record for me
    }

    // MARK: - Cancelled events

    func testCancellationIsDetectedFromTheTitlePrefix() {
        XCTAssertTrue(CalendarEvent.titleIndicatesCancellation("Canceled: Weekly Design Session"))
        XCTAssertTrue(CalendarEvent.titleIndicatesCancellation("Cancelled: Weekly sync"))
        XCTAssertTrue(CalendarEvent.titleIndicatesCancellation("CANCELED: Shouty meeting"))
        XCTAssertTrue(CalendarEvent.titleIndicatesCancellation("  Canceled: leading space"))
    }

    func testOrdinaryTitlesAreNotTreatedAsCancelled() {
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation("Weekly check-in"))
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation("Discuss canceled orders"))
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation("Cancellation policy review"))
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation("Canceled"), "no colon, no cancellation")
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation(nil))
        XCTAssertFalse(CalendarEvent.titleIndicatesCancellation(""))
    }
}
