import XCTest
@testable import Grey_Eminence

/// Deciding which transcripts to re-attribute. The repair rewrites speaker
/// labels in place, so the guard on what it touches matters more than the
/// repair itself: undoing a manual attribution would be worse than leaving a
/// transcript collapsed.
@MainActor
final class SpeakerRepairTests: XCTestCase {

    private func meeting(speakers: [Speaker]) -> Meeting {
        let meeting = Meeting(title: "Test")
        meeting.segments = speakers.enumerated().map { index, speaker in
            let segment = TranscriptSegment(
                speaker: speaker,
                text: "line \(index)",
                startTime: Double(index) * 5,
                endTime: Double(index) * 5 + 4,
                isFinal: true
            )
            return segment
        }
        return meeting
    }

    func testCollapsedTranscriptIsACandidate() {
        let m = meeting(speakers: [.me, .other("Speaker"), .me, .other("Speaker")])
        XCTAssertTrue(SpeakerRepairService.isCollapsed(m))
    }

    func testAlreadySeparatedTranscriptIsLeftAlone() {
        let m = meeting(speakers: [.me, .other("Speaker 1"), .other("Speaker 2")])
        XCTAssertFalse(SpeakerRepairService.isCollapsed(m))
    }

    func testManuallyNamedSpeakersAreNeverDisturbed() {
        // The important one: a transcript where the user has named someone
        // must not be re-attributed, even though other lines are still
        // collapsed. Re-running would overwrite their work with numbers.
        let m = meeting(speakers: [.me, .other("Speaker"), .other("Erin O'Brien")])
        XCTAssertFalse(SpeakerRepairService.isCollapsed(m))
    }

    func testTranscriptWithOnlyTheUserIsNotACandidate() {
        // Nothing to separate — there is no remote speech.
        let m = meeting(speakers: [.me, .me, .me])
        XCTAssertFalse(SpeakerRepairService.isCollapsed(m))
    }

    func testEmptyTranscriptIsNotACandidate() {
        XCTAssertFalse(SpeakerRepairService.isCollapsed(meeting(speakers: [])))
    }

    func testCollapsedLabelMatchesWhatReProcessingWrites() {
        // If these ever drift, the repair silently finds nothing to do.
        XCTAssertEqual(SpeakerRepairService.collapsedLabel, "Speaker")
        XCTAssertEqual(Speaker.other("Speaker").displayName, SpeakerRepairService.collapsedLabel)
    }

    func testNumberedSpeakerIsNotMistakenForTheCollapsedLabel() {
        // "Speaker 1" starts with "Speaker"; a prefix check would treat an
        // already-repaired transcript as needing repair, forever.
        let m = meeting(speakers: [.me, .other("Speaker 1")])
        XCTAssertFalse(SpeakerRepairService.isCollapsed(m))
    }

    // MARK: - Outcomes

    func testOutcomesAreDistinguishable() {
        // The UI reports these differently: "couldn't tell voices apart" is
        // not the same as "the audio is gone", and neither is a failure.
        XCTAssertNotEqual(SpeakerRepairService.Outcome.singleVoice, .audioUnavailable)
        XCTAssertNotEqual(SpeakerRepairService.Outcome.notCollapsed, .singleVoice)
        XCTAssertNotEqual(
            SpeakerRepairService.Outcome.repaired(voices: 2, segments: 10),
            .repaired(voices: 3, segments: 10)
        )
    }
}
