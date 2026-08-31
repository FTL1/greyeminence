import XCTest
@testable import Grey_Eminence

final class SpeakerRosterTests: XCTestCase {
    func testSeedAddsMeAndAttendeesOnce() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat", "Jordan", "Pat"], meName: "Alex")
        XCTAssertEqual(roster.seats.map(\.name), ["Alex", "Pat", "Jordan"])
        XCTAssertTrue(roster.seats[0].isMe)
        XCTAssertTrue(roster.seats[0].isLocked)
    }

    func testSeedDoesNotAddAlexMorganNextToMeAlex() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Alex Morgan", "Jordan Hale"], meName: "Alex")
        XCTAssertEqual(roster.seats.filter(\.isMe).count, 1)
        XCTAssertFalse(roster.seats.contains { $0.name == "Alex Morgan" })
        XCTAssertTrue(roster.seats.contains { $0.name == "Jordan Hale" })
    }

    func testSpokenSeatsDropsDuplicateAlexMorganChip() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan Hale"], meName: "Alex")
        _ = roster.addSeat(name: "Alex Morgan")
        let alex = TranscriptSegment(speaker: .meNamed("Alex"), text: "hi", startTime: 0, endTime: 8, isFinal: true)
        let jordan = TranscriptSegment(speaker: .other("Jordan Hale"), text: "yo", startTime: 9, endTime: 10, isFinal: true)
        roster.bindNamedVoices(in: [alex, jordan])
        let spoken = roster.spokenSeats(in: [alex, jordan])
        XCTAssertEqual(spoken.filter(\.isMe).count, 1)
        XCTAssertEqual(spoken.filter { $0.name == "Alex Morgan" }.count, 0)
        XCTAssertEqual(spoken.map(\.name).sorted(), ["Alex", "Jordan Hale"].sorted())
        let percents = SpeakerTalkShare.percents(in: [alex, jordan])
        let meShare = roster.talkSharePercent(for: spoken.first { $0.isMe }!, percents: percents, in: [alex, jordan])
        XCTAssertEqual(meShare, 89)
    }

    func testAddSeatReusesMeForAlexMorgan() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: [], meName: "Alex")
        let seat = roster.addSeat(name: "Alex Morgan")
        XCTAssertTrue(seat.isMe)
        XCTAssertEqual(roster.seats.count, 1)
        XCTAssertEqual(roster.seats[0].name, "Alex")
    }

    func testCollapseAbsorbsExistingAlexMorganSeatIntoMe() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan Hale"], meName: "Alex")
        let extraID = UUID()
        roster.seats.append(
            SpeakerRoster.Seat(
                id: extraID,
                name: "Alex Morgan",
                contactID: extraID,
                isMe: false,
                isLocked: false,
                boundSpeakers: [.other("Alex Morgan")]
            )
        )
        roster.paintSeatID = extraID
        roster.collapseSamePersonSeats()
        XCTAssertEqual(roster.seats.filter(\.isMe).count, 1)
        XCTAssertFalse(roster.seats.contains { $0.name == "Alex Morgan" })
        XCTAssertEqual(roster.paintSeatID, roster.seats.first { $0.isMe }?.id)
        XCTAssertEqual(roster.seats.first { $0.isMe }?.contactID, extraID)
        XCTAssertTrue(
            roster.seats.first { $0.isMe }!.boundSpeakers.contains {
                $0.matchesIdentity(.other("Alex Morgan"))
            }
        )
        XCTAssertTrue(roster.seats.contains { $0.name == "Jordan Hale" })
    }

    func testSeedKeepsPatAndJordanSeparate() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat", "Jordan"], meName: "Alex")
        XCTAssertEqual(roster.seats.map(\.name), ["Alex", "Pat", "Jordan"])
    }

    func testBindAndUnboundVoices() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat"], meName: "Alex")
        let pat = roster.seats.first { $0.name == "Pat" }!
        roster.bind(detected: .other("guest-1"), to: pat.id)
        XCTAssertTrue(roster.seat(matching: .other("guest-1"))?.name == "Pat")

        let guest1 = TranscriptSegment(speaker: .other("guest-1"), text: "a", startTime: 0, endTime: 1, isFinal: true)
        let guest2 = TranscriptSegment(speaker: .other("guest-2"), text: "b", startTime: 1, endTime: 2, isFinal: true)
        let unbound = roster.unboundVoices(in: [guest1, guest2])
        XCTAssertEqual(unbound.map(\.displayName), ["speaker-2"])
    }

    func testSetLockedTogglesANamedSeat() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat"], meName: "Alex")
        let pat = roster.seats.first { $0.name == "Pat" }!
        XCTAssertFalse(pat.isLocked)
        roster.setLocked(pat.id, true)
        XCTAssertTrue(roster.seats.first { $0.name == "Pat" }!.isLocked)
        roster.setLocked(pat.id, false)
        XCTAssertFalse(roster.seats.first { $0.name == "Pat" }!.isLocked)
        XCTAssertTrue(roster.seats.first { $0.isMe }!.isLocked)
    }

    func testLockAllBoundSkipsEmptySeats() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat", "Jordan"], meName: "Alex")
        let pat = roster.seats.first { $0.name == "Pat" }!
        roster.bind(detected: .other("guest-1"), to: pat.id)
        roster.lockAllBound()
        XCTAssertTrue(roster.seats.first { $0.name == "Pat" }!.isLocked)
        XCTAssertFalse(roster.seats.first { $0.name == "Jordan" }!.isLocked)
    }

    func testToggleIsolatedClearsOnSecondClick() {
        let roster = SpeakerRoster()
        let pat = Speaker.other("Pat")
        roster.toggleIsolated(pat)
        XCTAssertTrue(roster.isolatedSpeaker?.matchesIdentity(pat) == true)
        roster.toggleIsolated(pat)
        XCTAssertNil(roster.isolatedSpeaker)
    }

    func testIsolationSpeakerUsesBoundVoice() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Pat"], meName: "Alex")
        let pat = roster.seats.first { $0.name == "Pat" }!
        roster.bind(detected: .other("guest-1"), to: pat.id)
        let guest = TranscriptSegment(speaker: .other("guest-1"), text: "hi", startTime: 0, endTime: 1, isFinal: true)
        XCTAssertEqual(roster.isolationSpeaker(for: pat, in: [guest]), .other("guest-1"))
        XCTAssertNil(roster.isolationSpeaker(for: pat, in: []))
    }

    func testBindNamedVoicesMapsFullNameToSeatAndAlexRemoteToMe() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan"], meName: "Alex")
        let segments = [
            TranscriptSegment(speaker: .other("Jordan Hale"), text: "a", startTime: 0, endTime: 1, isFinal: true),
            TranscriptSegment(speaker: .other("Alex"), text: "b", startTime: 1, endTime: 2, isFinal: true),
            TranscriptSegment(speaker: .other("guest-1"), text: "c", startTime: 2, endTime: 3, isFinal: true),
        ]
        roster.bindNamedVoices(in: segments)
        XCTAssertEqual(roster.seat(matching: .other("Jordan Hale"))?.name, "Jordan")
        XCTAssertTrue(roster.seat(matching: .other("Alex"))?.isMe == true)
        XCTAssertNil(roster.seat(matching: .other("guest-1")))
        XCTAssertEqual(roster.unboundVoices(in: segments).map(\.displayName), ["speaker-1"])
    }

    func testToggleHiddenSeatCoversEveryBoundIdentity() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan"], meName: "Alex")
        let jordanLine = TranscriptSegment(speaker: .other("Jordan Hale"), text: "a", startTime: 0, endTime: 1, isFinal: true)
        roster.bindNamedVoices(in: [jordanLine])
        let jordanSeat = roster.seats.first { $0.name == "Jordan" }!
        roster.toggleHidden(seat: jordanSeat, in: [jordanLine])
        XCTAssertTrue(roster.isSeatHidden(jordanSeat, in: [jordanLine]))
        let hidden = roster.hiddenIdentities(in: [jordanLine])
        XCTAssertTrue(hidden.contains { $0.matchesIdentity(.other("Jordan Hale")) })
    }

    func testAssigningGuestsToJordanUnifiesHideShow() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan Hale"], meName: "Alex")
        let native = TranscriptSegment(speaker: .other("Jordan Hale"), text: "native", startTime: 0, endTime: 1, isFinal: true)
        let guest1 = TranscriptSegment(speaker: .other("guest-1"), text: "g1", startTime: 2, endTime: 3, isFinal: true)
        let guest2 = TranscriptSegment(speaker: .other("guest-2"), text: "g2", startTime: 4, endTime: 5, isFinal: true)
        let me = TranscriptSegment(speaker: .meNamed("Alex"), text: "me", startTime: 6, endTime: 7, isFinal: true)
        let segments = [native, guest1, guest2, me]
        roster.bindNamedVoices(in: segments)
        let jordanSeat = roster.seats.first { $0.name == "Jordan Hale" }!

        guest1.speaker = .other("Jordan")
        guest2.speaker = .other("Jordan Hale")
        roster.adopt(from: .other("guest-1"), onto: jordanSeat.speaker, in: segments)
        roster.adopt(from: .other("guest-2"), onto: jordanSeat.speaker, in: segments)
        XCTAssertEqual(guest1.speaker, jordanSeat.speaker)
        XCTAssertEqual(guest2.speaker, jordanSeat.speaker)

        roster.toggleHidden(seat: jordanSeat, in: segments)
        let items = TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: roster.hiddenIdentities(in: segments),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        let playable = items.compactMap { item -> String? in
            if case .segment(let segment) = item { return segment.text }
            return nil
        }
        XCTAssertEqual(playable, ["me"])
        XCTAssertFalse(playable.contains("native"))
        XCTAssertFalse(playable.contains("g1"))
        XCTAssertEqual(items.filter { if case .collapsed = $0 { return true }; return false }.count, 1)

        roster.reveal(jordanSeat.speaker, in: segments)
        let shown = TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: roster.hiddenIdentities(in: segments),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        let shownTexts = shown.compactMap { item -> String? in
            if case .segment(let segment) = item { return segment.text }
            return nil
        }
        XCTAssertEqual(Set(shownTexts), ["native", "g1", "g2", "me"])
    }

    func testAdoptingHiddenGuestDoesNotHideJordan() {
        let roster = SpeakerRoster()
        roster.seed(attendeeNames: ["Jordan Hale"], meName: "Alex")
        let native = TranscriptSegment(speaker: .other("Jordan Hale"), text: "native", startTime: 0, endTime: 1, isFinal: true)
        let guest = TranscriptSegment(speaker: .other("guest-1"), text: "g1", startTime: 2, endTime: 3, isFinal: true)
        roster.bindNamedVoices(in: [native, guest])
        roster.toggleHidden(.other("guest-1"))
        XCTAssertTrue(roster.isHidden(.other("guest-1")))
        roster.adopt(from: .other("guest-1"), onto: .other("Jordan Hale"), in: [native, guest])
        guest.speaker = .other("Jordan Hale")
        XCTAssertFalse(roster.isSeatHidden(roster.seats.first { $0.name == "Jordan Hale" }!, in: [native, guest]))
        let items = TranscriptDisplay.items(
            from: [native, guest],
            hiddenSpeakers: roster.hiddenIdentities(in: [native, guest]),
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        XCTAssertEqual(items.compactMap { if case .segment(let s) = $0 { return s.text }; return nil }, ["native", "g1"])
    }

    func testMixerGenerationBumpsOnHideShowAndIsolate() {
        let roster = SpeakerRoster()
        XCTAssertEqual(roster.mixerGeneration, 0)
        roster.toggleHidden(.other("guest-1"))
        XCTAssertEqual(roster.mixerGeneration, 1)
        roster.toggleHidden(.other("guest-1"))
        XCTAssertEqual(roster.mixerGeneration, 2)
        roster.toggleIsolated(.other("guest-2"))
        XCTAssertEqual(roster.mixerGeneration, 3)
        roster.showAllSpeakers()
        XCTAssertEqual(roster.mixerGeneration, 4)
    }
}
