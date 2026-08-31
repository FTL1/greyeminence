import XCTest
@testable import Grey_Eminence

final class TranscriptAutoMergeTests: XCTestCase {
    private func line(_ speaker: Speaker, _ text: String, from: TimeInterval, to: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(speaker: speaker, text: text, startTime: from, endTime: to, isFinal: true)
    }

    func testGroupsSameSpeakerWithinWindow() {
        let alex = Speaker.meNamed("Alex")
        let segments = [
            line(alex, "as", from: 66, to: 67),
            line(alex, "general", from: 67, to: 68),
            line(alex, "specific info", from: 72, to: 74)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 10, pause: 5)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].map(\.text), ["as", "general", "specific info"])
    }

    func testStopsAtOtherSpeaker() {
        let alex = Speaker.meNamed("Alex")
        let jordan = Speaker.other("Jordan Hale")
        let segments = [
            line(alex, "hello", from: 0, to: 1),
            line(jordan, "hi", from: 1.2, to: 2),
            line(alex, "again", from: 2.1, to: 3)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 30, pause: 2)
        XCTAssertEqual(groups.map { $0.map(\.text) }, [["hello"], ["hi"], ["again"]])
    }

    func testStopsAtPause() {
        let alex = Speaker.meNamed("Alex")
        let segments = [
            line(alex, "first", from: 0, to: 1),
            line(alex, "later", from: 5, to: 6)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 30, pause: 2)
        XCTAssertEqual(groups.count, 2)
    }

    func testStopsAtMaxWindow() {
        let alex = Speaker.meNamed("Alex")
        let segments = [
            line(alex, "a", from: 0, to: 1),
            line(alex, "b", from: 3, to: 4),
            line(alex, "c", from: 9, to: 11)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 10, pause: 6)
        XCTAssertEqual(groups.map { $0.map(\.text) }, [["a", "b"], ["c"]])
    }

    func testSkipsNotes() {
        let alex = Speaker.meNamed("Alex")
        let segments = [
            line(alex, "talk", from: 0, to: 1),
            line(alex, "[Note] remember this", from: 1.1, to: 1.2),
            line(alex, "more talk", from: 1.3, to: 2)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 30, pause: 2)
        XCTAssertEqual(groups.map { $0.map(\.text) }, [["talk"], ["[Note] remember this"], ["more talk"]])
    }

    func testJoinDedupPrefixAndDuplicate() {
        XCTAssertEqual(
            TranscriptAutoMerge.joinTexts(["as", "as possible while giving enough", "specific info"]),
            "as possible while giving enough specific info"
        )
        XCTAssertEqual(TranscriptAutoMerge.joinTexts(["Yeah.", "Yeah."]), "Yeah.")
        XCTAssertEqual(
            TranscriptAutoMerge.joinTexts(["I meant to take Chris off there.", "Yeah."]),
            "I meant to take Chris off there. Yeah."
        )
    }

    func testJoinKeepsLongerWhenIncomingIsShorterPrefix() {
        XCTAssertEqual(
            TranscriptAutoMerge.joinTexts(["the cabinet count is locked", "the cabinet count"]),
            "the cabinet count is locked"
        )
    }

    func testZeroDurationFragmentsThreeSecondsApartStillMerge() {
        let guest = Speaker.other("guest-1")
        let segments = [
            line(guest, "If we want to talk about what this update", from: 7, to: 7),
            line(guest, "what the initial scope", from: 10, to: 10),
            line(guest, "the initial scope of this isn't for a particular", from: 12, to: 12),
            line(guest, "of this isn't for a particular megawatts as much.", from: 14, to: 14),
            line(guest, "I think it is, within the 100", from: 15, to: 15)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 15, pause: 4)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 5)
    }

    func testOtherSpeakerStillSplitsScreenshotPattern() {
        let alex = Speaker.meNamed("Alex")
        let guest = Speaker.other("guest-1")
        let segments = [
            line(alex, "allow. Okay, microphone.", from: 0, to: 5),
            line(guest, "If we want to talk about what this update", from: 7, to: 10),
            line(guest, "what the initial scope", from: 10, to: 12),
            line(alex, "But really, the engineering", from: 22, to: 25)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 15, pause: 4)
        XCTAssertEqual(groups.map { $0.map(\.speaker.displayName) }, [
            ["Alex"],
            ["speaker-1", "speaker-1"],
            ["Alex"]
        ])
    }

    func testCoveredEndUsesNextLineWhenLastCrumbHasNoDuration() {
        let guest = Speaker.other("Jordan Hale")
        let group = [
            line(guest, "data center, the retrofit", from: 27, to: 27),
            line(guest, "got to pick a number", from: 31, to: 31),
            line(guest, "enough base infrastructure", from: 33, to: 33)
        ]
        XCTAssertEqual(TranscriptAutoMerge.coveredEnd(of: group, followingStart: 41), 41, accuracy: 0.01)
    }

    func testPlaybackEndExtendsTruncatedMergeToNextLine() {
        let guest = Speaker.other("Jordan Hale")
        let segment = line(guest, "data center, the retrofit of the data center", from: 27, to: 33)
        segment.isEdited = true
        XCTAssertEqual(TranscriptAutoMerge.playbackEnd(segment: segment, nextStart: 41), 41, accuracy: 0.01)
        segment.isEdited = false
        segment.endTime = 33
        XCTAssertEqual(TranscriptAutoMerge.playbackEnd(segment: segment, nextStart: 41), 33, accuracy: 0.01)
    }

    func testOverlapCountsAsNoPause() {
        let alex = Speaker.meNamed("Alex")
        let segments = [
            line(alex, "I meant to take Chris off there.", from: 96, to: 98),
            line(alex, "Yeah.", from: 96, to: 97)
        ]
        let groups = TranscriptAutoMerge.groups(in: segments, maxWindow: 10, pause: 2)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
    }
}
