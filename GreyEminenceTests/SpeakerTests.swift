import XCTest
@testable import Grey_Eminence

final class SpeakerTests: XCTestCase {

    override func tearDown() {
        SpeakerNames.resetSession()
        super.tearDown()
    }

    func testDefaultMeDisplayName() {
        let expected = SpeakerNames.effectiveMeName ?? "Me"
        XCTAssertEqual(Speaker.me.displayName, expected)
        XCTAssertTrue(Speaker.me.isMe)
    }

    func testLegacySpeakerNamesPrettyPrintAsSpeakerN() {
        XCTAssertEqual(Speaker.prettyRemoteName("Speaker"), "speaker-1")
        XCTAssertEqual(Speaker.prettyRemoteName("Speaker 1"), "speaker-1")
        XCTAssertEqual(Speaker.prettyRemoteName("Speaker1"), "speaker-1")
        XCTAssertEqual(Speaker.prettyRemoteName("Speaker 2"), "speaker-2")
        XCTAssertEqual(Speaker.prettyRemoteName("guest-1"), "speaker-1")
        XCTAssertEqual(Speaker.prettyRemoteName("unknown-2"), "speaker-2")
        XCTAssertEqual(Speaker.other("Speaker").displayName, "speaker-1")
        XCTAssertEqual(Speaker.other("Jordan").displayName, "Jordan")
        XCTAssertEqual(Speaker.guestLabel(index: 3), "speaker-3")
        XCTAssertEqual(Speaker.unknownLabel(index: 1), "speaker-1")
        XCTAssertEqual(Speaker.other("unknown-3").displayName, "speaker-3")
        XCTAssertTrue(Speaker.other("speaker-1").isGuestPlaceholder)
    }

    func testMeNamedDisplayNameAndIdentity() {
        let named = Speaker.meNamed("Alex Morgan")
        XCTAssertEqual(named.displayName, "Alex Morgan")
        XCTAssertTrue(named.isMe)
        XCTAssertTrue(named.matchesIdentity(.me))
        XCTAssertTrue(Speaker.me.matchesIdentity(named))
        XCTAssertEqual(named.initials, "CL")
        XCTAssertFalse(named.matchesIdentity(.other("Alex Morgan")))
    }

    func testEmptyMeNamedFallsBackToMe() {
        XCTAssertEqual(Speaker.meNamed("   ").displayName, SpeakerNames.effectiveMeName ?? "Me")
    }

    func testResolvedMeUsesSessionThenGlobal() {
        XCTAssertEqual(Speaker.resolvedMe(sessionName: nil, globalName: nil), .me)
        XCTAssertEqual(Speaker.resolvedMe(sessionName: nil, globalName: "Alex"), .meNamed("Alex"))
        XCTAssertEqual(Speaker.resolvedMe(sessionName: "Session Alex", globalName: "Alex"), .meNamed("Session Alex"))
        XCTAssertEqual(Speaker.resolvedMe(sessionName: "  ", globalName: "Alex"), .meNamed("Alex"))
    }

    func testRenamedPreservesLocalIdentity() {
        XCTAssertEqual(Speaker.renamed(from: .me, displayName: "Alex"), .meNamed("Alex"))
        XCTAssertEqual(Speaker.renamed(from: .meNamed("Alex"), displayName: "me"), .me)
        XCTAssertEqual(Speaker.renamed(from: .other("Speaker 1"), displayName: "Alice"), .other("Alice"))
        XCTAssertEqual(Speaker.renamed(from: .other("Speaker 1"), displayName: "  "), .other("Speaker 1"))
    }

    func testEffectiveMeNamePrefersSession() {
        XCTAssertEqual(SpeakerNames.effectiveMeName(session: "A", global: "B"), "A")
        XCTAssertEqual(SpeakerNames.effectiveMeName(session: "  ", global: "B"), "B")
        XCTAssertNil(SpeakerNames.effectiveMeName(session: nil, global: nil))
    }

    func testSessionSetDoesNotWriteGlobalUnlessAsked() {
        let suite = UserDefaults(suiteName: "SpeakerTests.\(UUID().uuidString)")!
        let previous = UserDefaults.standard.string(forKey: SpeakerNames.globalMeDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: SpeakerNames.globalMeDisplayNameKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: SpeakerNames.globalMeDisplayNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SpeakerNames.globalMeDisplayNameKey)
            }
            _ = suite
        }

        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        XCTAssertEqual(SpeakerNames.sessionMeDisplayName, "Alex")
        XCTAssertNil(UserDefaults.standard.string(forKey: SpeakerNames.globalMeDisplayNameKey))

        SpeakerNames.setSessionMeName("Blake", saveAsDefault: true)
        XCTAssertEqual(SpeakerNames.sessionMeDisplayName, "Blake")
        XCTAssertEqual(UserDefaults.standard.string(forKey: SpeakerNames.globalMeDisplayNameKey), "Blake")
        UserDefaults.standard.removeObject(forKey: SpeakerNames.globalMeDisplayNameKey)
    }

    func testOldMeStillDecodes() throws {
        let data = try JSONEncoder().encode(Speaker.me)
        let decoded = try JSONDecoder().decode(Speaker.self, from: data)
        XCTAssertEqual(decoded, .me)

        let named = Speaker.meNamed("Alex")
        let namedData = try JSONEncoder().encode(named)
        XCTAssertEqual(try JSONDecoder().decode(Speaker.self, from: namedData), named)
    }

    func testRosterFallbackExcludesRenamedMe() {
        let segments = [
            SegmentSnapshot(speaker: .meNamed("Alex"), text: "hello", formattedTimestamp: "", isFinal: true),
            SegmentSnapshot(speaker: .other("Carlos"), text: "hi", formattedTimestamp: "", isFinal: true),
        ]
        let effective = AIIntelligenceService.rosterForFiltering(nil, segments: segments)
        XCTAssertEqual(Set(effective.otherAttendees), ["Carlos"])
        XCTAssertEqual(effective.myName, "Alex")
        XCTAssertTrue(effective.isOneOnOne)
    }

    func testTalkShareUsesSegmentDuration() {
        let mine = TranscriptSegment(speaker: .me, text: "a", startTime: 0, endTime: 30)
        let theirs = TranscriptSegment(speaker: .other("Alice"), text: "b", startTime: 30, endTime: 70)
        XCTAssertEqual(SpeakerTalkShare.percent(for: .me, in: [mine, theirs]), 43)
        XCTAssertEqual(SpeakerTalkShare.percent(for: .other("Alice"), in: [mine, theirs]), 57)
        XCTAssertEqual(SpeakerTalkShare.percent(for: .other("Bob"), in: [mine, theirs]), 0)
    }

    func testTalkShareTreatsMeNamedAsSamePerson() {
        let mine = TranscriptSegment(speaker: .meNamed("Alex"), text: "a", startTime: 0, endTime: 10)
        let extra = TranscriptSegment(speaker: .me, text: "b", startTime: 10, endTime: 20)
        let other = TranscriptSegment(speaker: .other("Alice"), text: "c", startTime: 20, endTime: 40)
        XCTAssertEqual(SpeakerTalkShare.percent(for: .me, in: [mine, extra, other]), 50)
    }

    func testTalkShareEmptyIsZero() {
        XCTAssertEqual(SpeakerTalkShare.percent(for: .me, in: []), 0)
    }

    func testTalkShareLeadersOrdersAndCaps() {
        let alex = TranscriptSegment(speaker: .meNamed("Alex"), text: "a", startTime: 0, endTime: 50)
        let pat = TranscriptSegment(speaker: .other("Pat"), text: "b", startTime: 50, endTime: 80)
        let riley = TranscriptSegment(speaker: .other("Riley"), text: "c", startTime: 80, endTime: 100)
        let leaders = SpeakerTalkShare.leaders(in: [alex, pat, riley], limit: 2)
        XCTAssertEqual(leaders.map(\.speaker.displayName), ["Alex", "Pat"])
        XCTAssertEqual(leaders.map(\.percent), [50, 30])
        XCTAssertTrue(SpeakerTalkShare.leaders(in: [], limit: 3).isEmpty)
    }

    func testHiddenSpeakerLeavesOneClickableStub() {
        let alice1 = TranscriptSegment(speaker: .other("Alice"), text: "one", startTime: 0, endTime: 1)
        let me = TranscriptSegment(speaker: .me, text: "two", startTime: 1, endTime: 2)
        let alice2 = TranscriptSegment(speaker: .other("Alice"), text: "three", startTime: 2, endTime: 3)
        let items = TranscriptDisplay.items(
            from: [alice1, me, alice2],
            hiddenSpeakers: [.other("Alice")],
            isolatedSpeaker: nil,
            searchSpeaker: nil,
            searchQuery: ""
        )
        XCTAssertEqual(items.count, 2)
        guard case .collapsed(let speaker, let count) = items[0] else {
            return XCTFail("expected collapsed Alice stub first")
        }
        XCTAssertTrue(speaker.matchesIdentity(.other("Alice")))
        XCTAssertEqual(count, 2)
        XCTAssertEqual(items[0].id, Speaker.other("Alice").identityKey.hideStubID)
        XCTAssertNotEqual(items[0].id, "segment:\(alice1.id.uuidString)")
        XCTAssertNotEqual(items[0].id, alice1.id.uuidString)
        XCTAssertEqual(TranscriptDisplayItem.scrollID(for: alice1.id), "segment:\(alice1.id.uuidString)")
        guard case .segment(let kept) = items[1] else {
            return XCTFail("expected remaining Me segment")
        }
        XCTAssertTrue(kept.speaker.isMe)
    }

    func testJordanMatchesJordanHaleIdentity() {
        XCTAssertTrue(Speaker.other("Jordan").matchesIdentity(.other("Jordan Hale")))
        XCTAssertTrue(Speaker.other("Jordan Hale").matchesIdentity(.other("Jordan")))
        XCTAssertFalse(Speaker.other("guest-1").matchesIdentity(.other("Jordan Hale")))
        XCTAssertEqual(
            Speaker.other("Jordan Hale").identityKey,
            Speaker.other("jordan  hale").identityKey
        )
    }

    func testGuestPlaceholderAndNamedIdentity() {
        XCTAssertTrue(Speaker.other("guest-1").isGuestPlaceholder)
        XCTAssertTrue(Speaker.other("guest-2").isGuestPlaceholder)
        XCTAssertTrue(Speaker.other("Speaker 2").isGuestPlaceholder)
        XCTAssertFalse(Speaker.other("Pat").isGuestPlaceholder)
        XCTAssertFalse(Speaker.me.isGuestPlaceholder)
    }

    func testResolvedLabelDoesNotTurnNamedVoiceIntoNewGuest() {
        XCTAssertEqual(
            SpeakerContinuity.resolvedLabel(current: .other("Pat"), proposed: .other("guest-2")),
            .other("Pat")
        )
        XCTAssertEqual(
            SpeakerContinuity.resolvedLabel(current: .other("guest-1"), proposed: .other("guest-2")),
            .other("guest-2")
        )
        XCTAssertEqual(
            SpeakerContinuity.resolvedLabel(current: .other("Pat"), proposed: .other("Jordan")),
            .other("Jordan")
        )
    }

    func testStickyRemotePrefersRecentNamedGuest() {
        let pat = TranscriptSegment(speaker: .other("Pat"), text: "first", startTime: 10, endTime: 12, isFinal: true)
        let me = TranscriptSegment(speaker: .me, text: "ok", startTime: 12, endTime: 13, isFinal: true)
        XCTAssertEqual(
            SpeakerContinuity.stickyRemote(at: 16, in: [pat, me]),
            .other("Pat")
        )
        XCTAssertNil(SpeakerContinuity.stickyRemote(at: 40, in: [pat, me]))
    }

    func testSpeakerSearchMatchesOnlyThatSpeaker() {
        let alice1 = TranscriptSegment(speaker: .other("Alice"), text: "I can hear you", startTime: 0, endTime: 1)
        let me = TranscriptSegment(speaker: .me, text: "I hear the same", startTime: 1, endTime: 2)
        let alice2 = TranscriptSegment(speaker: .other("Alice"), text: "Did you hear that", startTime: 2, endTime: 3)
        let alice3 = TranscriptSegment(speaker: .other("Alice"), text: "never mind", startTime: 3, endTime: 4)
        let matches = SpeakerSearch.matchingSegments(
            query: "hear",
            speaker: .other("Alice"),
            in: [alice1, me, alice2, alice3]
        )
        XCTAssertEqual(matches.map(\.id), [alice1.id, alice2.id])
    }

    func testSpeakerSearchIgnoresBlankQuery() {
        let alice = TranscriptSegment(speaker: .other("Alice"), text: "hello", startTime: 0, endTime: 1)
        XCTAssertTrue(SpeakerSearch.matchingSegments(query: "   ", speaker: .other("Alice"), in: [alice]).isEmpty)
    }

    func testSpeakerSearchNearestMatchAfterAnchor() {
        let first = TranscriptSegment(speaker: .other("Alice"), text: "hear one", startTime: 0, endTime: 1)
        let second = TranscriptSegment(speaker: .other("Alice"), text: "hear two", startTime: 10, endTime: 11)
        let third = TranscriptSegment(speaker: .other("Alice"), text: "hear three", startTime: 20, endTime: 21)
        let matches = [first, second, third]
        XCTAssertEqual(SpeakerSearch.nearestMatchIndex(in: matches, after: 10), 1)
        XCTAssertEqual(SpeakerSearch.nearestMatchIndex(in: matches, after: 15), 2)
        XCTAssertEqual(SpeakerSearch.nearestMatchIndex(in: matches, after: 25), 0)
    }

    func testAnonymousRemoteDetectsCollapsedLabel() {
        XCTAssertTrue(Speaker.other("Speaker").isAnonymousRemote)
        XCTAssertTrue(Speaker.other("other").isAnonymousRemote)
        XCTAssertFalse(Speaker.other("Speaker 1").isAnonymousRemote)
        XCTAssertFalse(Speaker.other("Jordan").isAnonymousRemote)
        XCTAssertFalse(Speaker.me.isAnonymousRemote)
    }

    func testOverlapAssignerPrefersContainingRange() {
        let ranges: [(speaker: Speaker, start: TimeInterval, end: TimeInterval)] = [
            (.other("Speaker 1"), 0, 10),
            (.other("Speaker 2"), 10, 20),
        ]
        XCTAssertEqual(
            SpeakerOverlapAssigner.speaker(forStart: 12, end: 14, in: ranges),
            .other("Speaker 2")
        )
        XCTAssertEqual(
            SpeakerOverlapAssigner.speaker(forStart: 1, end: 2, in: ranges),
            .other("Speaker 1")
        )
    }

    func testHasCollapsedRemotes() {
        let segs = [
            TranscriptSegment(speaker: .me, text: "hi", startTime: 0, endTime: 1),
            TranscriptSegment(speaker: .other("Speaker"), text: "a", startTime: 1, endTime: 2),
            TranscriptSegment(speaker: .other("Speaker"), text: "b", startTime: 2, endTime: 3),
        ]
        XCTAssertTrue(MeetingSpeakerRecovery.hasCollapsedRemotes(in: segs))
        segs[2].speaker = .other("Speaker 2")
        XCTAssertFalse(MeetingSpeakerRecovery.hasCollapsedRemotes(in: segs))
    }

    func testTranscriptHighlightMarksEveryOccurrence() {
        let marked = String(TranscriptTextHighlight.attributed("Hear me hear you", query: "hear").characters)
        XCTAssertEqual(marked, "Hear me hear you")
        let empty = TranscriptTextHighlight.attributed("hello", query: "hear")
        XCTAssertEqual(String(empty.characters), "hello")
    }

    func testSelfIntroductionClaimsFirstPersonName() {
        XCTAssertEqual(
            SpeakerSelfIntroduction.claimedName(in: "Nice to meet you, I'm Bob Dipshit."),
            "Bob Dipshit"
        )
        XCTAssertEqual(
            SpeakerSelfIntroduction.claimedName(in: "Hi, I am Pat."),
            "Pat"
        )
        XCTAssertEqual(
            SpeakerSelfIntroduction.claimedName(in: "My name is Jordan Hale"),
            "Jordan Hale"
        )
        XCTAssertNil(SpeakerSelfIntroduction.claimedName(in: "I'm going to share my screen."))
        XCTAssertNil(SpeakerSelfIntroduction.claimedName(in: "This is Bob over here."))
    }

    func testSelfIntroductionRenamesPlaceholderToInvitee() {
        let intro = TranscriptSegment(
            speaker: .other("speaker-1"),
            text: "Nice to meet you, I'm Bob.",
            startTime: 12,
            endTime: 16,
            isFinal: true
        )
        let later = TranscriptSegment(
            speaker: .other("speaker-1"),
            text: "The ROM is wrong.",
            startTime: 90,
            endTime: 94,
            isFinal: true
        )
        let me = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "This is Bob on the call.",
            startTime: 8,
            endTime: 10,
            isFinal: true
        )
        let changed = SpeakerSelfIntroduction.apply(
            segments: [me, intro, later],
            inviteeNames: ["Bob Dipshit", "Jordan Hale"],
            myLabels: ["Alex", "Me"]
        )
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(intro.speaker, .other("Bob Dipshit"))
        XCTAssertEqual(later.speaker, .other("Bob Dipshit"))
        XCTAssertTrue(me.speaker.isMe)
    }

    func testSelfIntroductionIgnoresMeAndLateLines() {
        let late = TranscriptSegment(
            speaker: .other("speaker-2"),
            text: "I'm Bob.",
            startTime: 20 * 60,
            endTime: 20 * 60 + 2,
            isFinal: true
        )
        XCTAssertEqual(
            SpeakerSelfIntroduction.apply(
                segments: [late],
                inviteeNames: ["Bob Dipshit"],
                myLabels: ["Alex"]
            ),
            0
        )
        XCTAssertEqual(late.speaker, .other("speaker-2"))
    }
}
