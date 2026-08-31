import XCTest
@testable import Grey_Eminence

final class SpeakerReanalyzeTests: XCTestCase {
    func testUnknownLabels() {
        XCTAssertEqual(Speaker.unknownLabel(index: 1), "speaker-1")
        XCTAssertEqual(Speaker.unknownLabel(index: 0), "speaker-1")
        XCTAssertEqual(Speaker.unknownIndex(fromName: "unknown-2"), 2)
        XCTAssertTrue(Speaker.other("unknown-1").isUnknownPlaceholder)
        XCTAssertTrue(Speaker.other("unknown-1").isGuestPlaceholder)
        XCTAssertTrue(Speaker.other("unknown-1").displayNameIsPlaceholder)
        XCTAssertEqual(Speaker.other("unknown-2").displayName, "speaker-2")
        XCTAssertFalse(Speaker.other("Jordan").isUnknownPlaceholder)
    }

    func testNameMatcherGroupsShortAndFullName() {
        XCTAssertTrue(SpeakerNameMatcher.samePerson("Jordan", "Jordan Hale"))
        XCTAssertTrue(SpeakerNameMatcher.samePerson("Alex", "Alex Morgan"))
        XCTAssertFalse(SpeakerNameMatcher.samePerson("Jordan", "guest-1"))
        XCTAssertFalse(SpeakerNameMatcher.samePerson("unknown-1", "Jordan"))
        XCTAssertFalse(SpeakerNameMatcher.samePerson("Ann", "Anna"))
        XCTAssertFalse(SpeakerNameMatcher.samePerson("Sam", "Jordan"))
    }

    func testUnmatchedStyleLabels() {
        XCTAssertEqual(UnmatchedSpeakerStyle.guest.label(index: 2), "speaker-2")
        XCTAssertEqual(UnmatchedSpeakerStyle.unknown.label(index: 2), "speaker-2")
    }

    func testHidingJordanSeatHidesEarlyLinesAndKeepsUnknownGuest() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan"], meName: "Alex")
        let jordan = TranscriptSegment(
            speaker: .other("Jordan Hale"),
            text: "early jordan",
            startTime: 13,
            endTime: 16,
            isFinal: true
        )
        let alexRemote = TranscriptSegment(
            speaker: .other("Alex"),
            text: "early alex",
            startTime: 24,
            endTime: 27,
            isFinal: true
        )
        let guest = TranscriptSegment(
            speaker: .other("guest-1"),
            text: "unlabeled",
            startTime: 40,
            endTime: 44,
            isFinal: true
        )
        let me = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "later me",
            startTime: 50,
            endTime: 53,
            isFinal: true
        )
        let laterJordan = TranscriptSegment(
            speaker: .other("Jordan Hale"),
            text: "later jordan",
            startTime: 60,
            endTime: 63,
            isFinal: true
        )
        let segments = [jordan, alexRemote, guest, me, laterJordan]
        roster.bindNamedVoices(in: segments)

        let meSeat = roster.seats.first { $0.isMe }!
        let jordanSeat = roster.seats.first { $0.name == "Jordan" }!
        XCTAssertTrue(jordanSeat.binds(.other("Jordan Hale")))
        XCTAssertTrue(meSeat.binds(.other("Alex")))

        roster.toggleHidden(seat: meSeat, in: segments)
        roster.toggleHidden(seat: jordanSeat, in: segments)

        let items = TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: roster.hiddenIdentities(in: segments),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        let visibleTexts = items.compactMap { item -> String? in
            if case .segment(let segment) = item { return segment.text }
            return nil
        }
        XCTAssertEqual(visibleTexts, ["unlabeled"])
        XCTAssertFalse(visibleTexts.contains("early jordan"))
        XCTAssertFalse(visibleTexts.contains("early alex"))
    }

    func testHidingMeHidesFirstAlexLineAtZero() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: [], meName: "Alex")
        let first = TranscriptSegment(
            speaker: .other("Alex"),
            text: "schedule for classes",
            startTime: 0,
            endTime: 8,
            isFinal: true
        )
        let guest = TranscriptSegment(
            speaker: .other("guest-1"),
            text: "Yeah.",
            startTime: 40,
            endTime: 41,
            isFinal: true
        )
        let laterMe = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "later",
            startTime: 50,
            endTime: 51,
            isFinal: true
        )
        let segments = [first, guest, laterMe]
        roster.bindNamedVoices(in: segments)
        let meSeat = roster.seats.first { $0.isMe }!
        roster.toggleHidden(seat: meSeat, in: segments)
        let items = TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: roster.hiddenIdentities(in: segments),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        let visible = items.compactMap { item -> String? in
            if case .segment(let segment) = item { return segment.text }
            return nil
        }
        XCTAssertEqual(visible, ["Yeah."], "hiding you must not swallow guest-1")
        XCTAssertFalse(visible.contains("schedule for classes"))
        XCTAssertFalse(items.contains { item in
            if case .segment(let segment) = item { return segment.id == first.id }
            return false
        })
        XCTAssertTrue(items.contains { item in
            if case .collapsed(let speaker, let count) = item {
                return speaker.isMe && count == 2
            }
            return false
        })
        XCTAssertNotEqual(items.first { if case .collapsed = $0 { return true }; return false }?.id, "segment:\(first.id.uuidString)")
    }

    func testHideStubIdentityNeverMatchesFirstSegmentID() {
        let first = TranscriptSegment(speaker: .other("guest-1"), text: "Yeah.", startTime: 40, endTime: 41, isFinal: true)
        let second = TranscriptSegment(speaker: .other("guest-1"), text: "later", startTime: 50, endTime: 51, isFinal: true)
        let items = TranscriptDisplay.items(
            from: [first, second],
            hiddenSpeakers: [.other("guest-1")],
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        XCTAssertEqual(items.count, 1)
        guard case .collapsed(_, let count) = items[0] else {
            return XCTFail("expected a hide stub")
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(items[0].id, Speaker.other("guest-1").identityKey.hideStubID)
        XCTAssertFalse(items[0].id.contains(first.id.uuidString))
    }

    func testPlaceholderCatalogIncludesUnknown() {
        XCTAssertTrue(SpeakerLinkCatalog.isPlaceholder("unknown-1"))
        XCTAssertTrue(SpeakerLinkCatalog.isPlaceholder("unknown"))
    }

    /// Screenshot: Alex 0:00, guest-1 0:40, guest-2 11:55 stay playable after
    /// every mixer chip is off. Hide must drop those first snippets from the
    /// playable list and give stubs ids that cannot collide with them.
    func testHideAllMixerChipsLeavesNoPlayableFirstSnippets() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: [], meName: "Alex")
        let alexFirst = TranscriptSegment(
            speaker: .other("Alex"),
            text: "schedule for classes",
            startTime: 0,
            endTime: 8,
            isFinal: true
        )
        let guest1First = TranscriptSegment(
            speaker: .other("guest-1"),
            text: "Yeah.",
            startTime: 40,
            endTime: 41,
            isFinal: true
        )
        let guest1Later = TranscriptSegment(
            speaker: .other("guest-1"),
            text: "with",
            startTime: 60,
            endTime: 61,
            isFinal: true
        )
        let alexLater = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "later alex",
            startTime: 70,
            endTime: 71,
            isFinal: true
        )
        let guest2First = TranscriptSegment(
            speaker: .other("guest-2"),
            text: "it's where I",
            startTime: 715,
            endTime: 718,
            isFinal: true
        )
        let segments = [alexFirst, guest1First, guest1Later, alexLater, guest2First]
        roster.bindNamedVoices(in: segments)

        let meSeat = roster.seats.first { $0.isMe }!
        roster.toggleHidden(seat: meSeat, in: segments)
        roster.toggleHidden(.other("guest-1"))
        roster.toggleHidden(.other("guest-2"))

        let items = TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: roster.hiddenIdentities(in: segments),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        let playable = items.compactMap { item -> TranscriptSegment? in
            if case .segment(let segment) = item { return segment }
            return nil
        }
        XCTAssertTrue(playable.isEmpty, "first Alex / guest-1 / guest-2 lines must not stay playable")
        XCTAssertEqual(items.count, 3)

        let forbidden = [alexFirst, guest1First, guest2First].map(\.id.uuidString)
        for item in items {
            XCTAssertFalse(item.id.hasPrefix("segment:"), "hide stub \(item.id) must not use a segment identity")
            for uuid in forbidden {
                XCTAssertFalse(item.id.contains(uuid), "stub id \(item.id) collided with first-snippet UUID")
            }
        }
        XCTAssertEqual(
            items.map(\.id).sorted(),
            [
                Speaker.meNamed("Alex").identityKey.hideStubID,
                Speaker.other("guest-1").identityKey.hideStubID,
                Speaker.other("guest-2").identityKey.hideStubID,
            ].sorted()
        )
        XCTAssertGreaterThan(roster.mixerGeneration, 0)
    }

    func testPlayableRowIdentityIsNeverARawUUID() {
        let segment = TranscriptSegment(speaker: .other("guest-1"), text: "Yeah.", startTime: 40, endTime: 41, isFinal: true)
        let items = TranscriptDisplay.items(
            from: [segment],
            hiddenSpeakers: [],
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, TranscriptDisplayItem.scrollID(for: segment.id))
        XCTAssertNotEqual(items[0].id, segment.id.uuidString)
        XCTAssertNotEqual(items[0].id, Speaker.other("guest-1").identityKey.hideStubID)
    }
}