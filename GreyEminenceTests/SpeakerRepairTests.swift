import SwiftData
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

    // MARK: - Reversibility

    private func segment(_ speaker: Speaker, edited: Bool = false, original: Speaker? = nil) -> TranscriptSegment {
        let s = TranscriptSegment(speaker: speaker, text: "x", startTime: 0, endTime: 1, isFinal: true)
        s.isEdited = edited
        if let original {
            s.originalSpeakerData = try? JSONEncoder().encode(original)
        }
        return s
    }

    func testRepairedSegmentIsResettable() {
        let m = Meeting(title: "t")
        m.segments = [segment(.other("Speaker 2"), original: .other("Speaker"))]
        XCTAssertTrue(SpeakerRepairService.canResetLabels(m))
    }

    func testUntouchedTranscriptHasNothingToReset() {
        let m = Meeting(title: "t")
        m.segments = [segment(.other("Speaker")), segment(.me)]
        XCTAssertFalse(SpeakerRepairService.canResetLabels(m))
    }

    func testUserEditedSegmentIsNeverConsideredResettable() {
        // Their label is not ours to roll back, even though a stash exists —
        // the edit flow writes one too.
        let m = Meeting(title: "t")
        m.segments = [segment(.other("Erin"), edited: true, original: .other("Speaker 2"))]
        XCTAssertFalse(SpeakerRepairService.canResetLabels(m))
    }

    func testResetRestoresTheCollapsedLabelSoRepairCanRunAgain() {
        // The point of reset: a repaired transcript no longer looks collapsed,
        // so without this neither this service nor a better future diarizer
        // would ever revisit it.
        let m = Meeting(title: "t")
        m.segments = [segment(.other("Speaker 2"), original: .other("Speaker")), segment(.me)]
        XCTAssertFalse(SpeakerRepairService.isCollapsed(m), "repaired transcripts are not candidates")

        for s in m.segments where !s.isEdited && s.originalSpeakerData != nil {
            s.speakerData = s.originalSpeakerData!
            s.originalSpeakerData = nil
        }
        XCTAssertTrue(SpeakerRepairService.isCollapsed(m), "after reset it should be repairable again")
    }

    // MARK: - Cost of deciding

    func testAudioPresenceCheckDoesNotDependOnChunkDurations() {
        // The candidate scan asks "is there audio at all". Answering it by
        // resolving the windowed chunk list opens every file with AVAudioFile
        // to read a duration — tens of thousands of opens across the library,
        // on the main actor, which froze the settings pane on appear.
        let m = Meeting(title: "no audio on disk")
        let started = Date()
        _ = SpeakerRepairService.hasSystemAudio(for: m)
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 0.05,
            "presence check should be a filesystem lookup, not a decode"
        )
    }

    func testSurveyYieldsAndStaysCancellable() async {
        // A scan that can't be cancelled is a scan that hangs the window.
        // Survey carries SwiftData models, so it stays on the main actor;
        // what matters here is that it yields rather than blocking.
        let container = try! ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let survey = await SpeakerRepairService.survey(in: ModelContext(container))
        XCTAssertTrue(survey.repairable.isEmpty, "an empty store has no candidates")
        XCTAssertEqual(survey.resettableCount, 0)
    }

    // MARK: - One pass, two answers

    func testClassifyAnswersBothQuestionsConsistently() {
        // The pane needs "can this be repaired" and "can this be undone".
        // Asking separately walked every segment in the library twice.
        let m = Meeting(title: "t")
        m.segments = [segment(.me), segment(.other("Speaker"))]
        let c = SpeakerRepairService.classify(m)
        XCTAssertEqual(c.isCollapsed, SpeakerRepairService.isCollapsed(m))
        XCTAssertEqual(c.isResettable, SpeakerRepairService.canResetLabels(m))
    }

    func testRepairedMeetingIsResettableButNotRepairable() {
        let m = Meeting(title: "t")
        m.segments = [segment(.me), segment(.other("Speaker 2"), original: .other("Speaker"))]
        let c = SpeakerRepairService.classify(m)
        XCTAssertFalse(c.isCollapsed)
        XCTAssertTrue(c.isResettable)
    }

    func testCollapsedMeetingIsRepairableButNotResettable() {
        let m = Meeting(title: "t")
        m.segments = [segment(.me), segment(.other("Speaker"))]
        let c = SpeakerRepairService.classify(m)
        XCTAssertTrue(c.isCollapsed)
        XCTAssertFalse(c.isResettable)
    }

    func testPartlyNamedMeetingIsNeitherRepairableNorRolledBack() {
        // Hand-named speakers make the whole meeting off-limits, but a stash
        // from an earlier repair still counts as undoable.
        let m = Meeting(title: "t")
        m.segments = [
            segment(.other("Erin O\u{2019}Brien")),
            segment(.other("Speaker"), original: .other("Speaker")),
        ]
        let c = SpeakerRepairService.classify(m)
        XCTAssertFalse(c.isCollapsed, "a hand-named meeting must never be re-attributed")
        XCTAssertTrue(c.isResettable)
    }
}
