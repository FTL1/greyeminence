import XCTest
@testable import Grey_Eminence

final class SpeakerRelabelTests: XCTestCase {
    func testVisibleSegmentsHonorIsolation() {
        let (me, guest1, guest2) = sampleLines()
        let visible = SpeakerRelabel.visibleSegments(
            from: [me, guest1, guest2],
            hiddenSpeakers: [],
            isolatedSpeaker: .other("guest-1")
        )
        XCTAssertEqual(visible.map(\.text), ["guest-1"])
    }

    func testHiddenSpeakersAreNotVisible() {
        SpeakerNames.setSessionMeName("Alex", saveAsDefault: false)
        defer { SpeakerNames.resetSession() }
        let (me, guest1, guest2) = sampleLines()
        let visible = SpeakerRelabel.visibleSegments(
            from: [me, guest1, guest2],
            hiddenSpeakers: [.meNamed("Alex")],
            isolatedSpeaker: nil
        )
        XCTAssertEqual(visible.map(\.text), ["guest-1", "guest-2"])
    }

    func testRemoteRemapNeverMatchesMe() {
        XCTAssertTrue(SpeakerRelabel.shouldSkip(.meNamed("Alex"), remappingFrom: .other("guest-1")))
        XCTAssertFalse(SpeakerRelabel.shouldSkip(.other("guest-1"), remappingFrom: .other("guest-1")))
        XCTAssertFalse(SpeakerRelabel.matchesForRelabel(.meNamed("Alex"), current: .other("guest-1")))
        XCTAssertTrue(SpeakerRelabel.matchesForRelabel(.other("guest-1"), current: .other("guest-1")))
        XCTAssertFalse(SpeakerRelabel.matchesForRelabel(.other("guest-2"), current: .other("guest-1")))
    }

    /// Isolate Guest-1, then "select all" including hidden Me — only Guest-1 is assigned.
    func testSelectAllAfterIsolatingGuestDoesNotRemapMe() {
        let (me, guest1, guest2) = sampleLines()
        let selected = Set([me.id, guest1.id, guest2.id])
        let targets = SpeakerRelabel.assignmentTargets(
            selected: selected,
            segments: [me, guest1, guest2],
            hiddenSpeakers: [],
            isolatedSpeaker: .other("guest-1"),
            newSpeaker: .other("Jordan Hale")
        )
        XCTAssertEqual(targets.map(\.text), ["guest-1"])
        apply(targets, to: .other("Jordan Hale"))
        XCTAssertTrue(me.speaker.isMe)
        XCTAssertEqual(guest1.speaker, .other("Jordan Hale"))
        XCTAssertEqual(guest2.speaker, .other("guest-2"))
    }

    func testAssignmentTargetsDropHiddenMeEvenIfSelected() {
        let (me, guest1, _) = sampleLines()
        let targets = SpeakerRelabel.assignmentTargets(
            selected: [me.id, guest1.id],
            segments: [me, guest1],
            hiddenSpeakers: [.meNamed("Alex")],
            isolatedSpeaker: .other("guest-1"),
            newSpeaker: .other("Jordan Hale")
        )
        XCTAssertEqual(targets.map(\.text), ["guest-1"])
    }

    func testIdentityRemapSkipsMeWhenRenamingGuest() {
        let (me, guest1, guest2) = sampleLines()
        let current = Speaker.other("guest-1")
        let renamed = [me, guest1, guest2].filter {
            SpeakerRelabel.matchesForRelabel($0.speaker, current: current)
        }
        XCTAssertEqual(renamed.map(\.text), ["guest-1"])
    }

    func testAssigningAsMeCanTouchMeLines() {
        let (me, guest1, _) = sampleLines()
        let targets = SpeakerRelabel.assignmentTargets(
            selected: [me.id, guest1.id],
            segments: [me, guest1],
            hiddenSpeakers: [],
            isolatedSpeaker: nil,
            newSpeaker: Speaker.resolvedMe()
        )
        XCTAssertEqual(Set(targets.map(\.id)), [me.id, guest1.id])
    }

    func testUndoRestoresPreviousLabels() throws {
        let (me, guest1, _) = sampleLines()
        let undo = SpeakerLabelUndo()
        undo.capture([me, guest1])
        guest1.speaker = .other("Jordan Hale")
        me.speaker = .other("Jordan Hale")
        XCTAssertTrue(undo.canUndo)
        let snap = try XCTUnwrap(undo.pop())
        SpeakerLabelUndo.apply(snap, to: [me, guest1])
        XCTAssertTrue(me.speaker.isMe)
        XCTAssertEqual(guest1.speaker, .other("guest-1"))
        XCTAssertFalse(undo.canUndo)
    }

    private func sampleLines() -> (TranscriptSegment, TranscriptSegment, TranscriptSegment) {
        (
            TranscriptSegment(speaker: .meNamed("Alex"), text: "me", startTime: 0, endTime: 1, isFinal: true),
            TranscriptSegment(speaker: .other("guest-1"), text: "guest-1", startTime: 1, endTime: 2, isFinal: true),
            TranscriptSegment(speaker: .other("guest-2"), text: "guest-2", startTime: 2, endTime: 3, isFinal: true)
        )
    }

    private func apply(_ targets: [TranscriptSegment], to speaker: Speaker) {
        for segment in targets {
            segment.speaker = speaker
        }
    }
}
