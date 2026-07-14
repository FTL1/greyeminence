import XCTest
@testable import Grey_Eminence

/// Ownership filter for action items: the tool serves one user, so items
/// clearly owned by other attendees are dropped — except in a 1:1, where the
/// other person's commitments are promises to the user.
final class ActionItemOwnershipTests: XCTestCase {

    private let multiPersonRoster = MeetingRoster(myName: "Matthew Purdon", otherAttendees: ["Harsh", "Carlos", "Priya"])
    private let oneOnOneRoster = MeetingRoster(myName: "Matthew Purdon", otherAttendees: ["Carlos"])

    func testUnownedItemsAlwaysKept() {
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: nil, roster: multiPersonRoster))
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "  ", roster: multiPersonRoster))
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "null", roster: multiPersonRoster))
    }

    func testMyItemsAlwaysKept() {
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Me", roster: multiPersonRoster))
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Matthew Purdon", roster: multiPersonRoster))
        // First-name reference from the transcript still matches My Profile.
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Matthew", roster: multiPersonRoster))
    }

    func testDiarizationPlaceholdersCountAsUnclearOwnership() {
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Speaker 2", roster: multiPersonRoster))
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Unknown", roster: multiPersonRoster))
    }

    func testOtherAttendeesItemsDroppedInMultiPersonMeeting() {
        XCTAssertFalse(AIIntelligenceService.keepsActionItem(assignee: "Harsh", roster: multiPersonRoster))
        XCTAssertFalse(AIIntelligenceService.keepsActionItem(assignee: "Carlos", roster: multiPersonRoster))
        // Someone who isn't even an attendee is still not the user.
        XCTAssertFalse(AIIntelligenceService.keepsActionItem(assignee: "Karthik", roster: multiPersonRoster))
    }

    func testOtherPersonsItemsKeptInOneOnOne() {
        XCTAssertTrue(AIIntelligenceService.keepsActionItem(assignee: "Carlos", roster: oneOnOneRoster))
    }

    func testRosterForFilteringPrefersExplicitRoster() {
        let segments = [
            SegmentSnapshot(speaker: .me, text: "hello", formattedTimestamp: "", isFinal: true),
            SegmentSnapshot(speaker: .other("Speaker 1"), text: "hi", formattedTimestamp: "", isFinal: true),
        ]
        let effective = AIIntelligenceService.rosterForFiltering(multiPersonRoster, segments: segments)
        XCTAssertEqual(effective.otherAttendees, multiPersonRoster.otherAttendees)
    }

    func testRosterForFilteringFallsBackToTranscriptSpeakers() {
        let segments = [
            SegmentSnapshot(speaker: .me, text: "hello", formattedTimestamp: "", isFinal: true),
            SegmentSnapshot(speaker: .other("Carlos"), text: "hi", formattedTimestamp: "", isFinal: true),
            SegmentSnapshot(speaker: .other("Carlos"), text: "more", formattedTimestamp: "", isFinal: true),
        ]
        let effective = AIIntelligenceService.rosterForFiltering(nil, segments: segments)
        XCTAssertEqual(effective.otherAttendees, ["Carlos"])
        XCTAssertTrue(effective.isOneOnOne)
    }

    func testRosterBlockListsAttendeesAndOmitsWhenAlone() {
        let block = AIPromptTemplates.rosterBlock(multiPersonRoster)
        XCTAssertTrue(block.contains("Matthew Purdon"))
        XCTAssertTrue(block.contains("Harsh, Carlos, Priya"))

        XCTAssertEqual(AIPromptTemplates.rosterBlock(nil), "")
        XCTAssertEqual(AIPromptTemplates.rosterBlock(MeetingRoster(myName: "Matthew Purdon", otherAttendees: [])), "")
    }
}
