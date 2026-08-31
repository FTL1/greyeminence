import XCTest
@testable import Grey_Eminence

final class LibrarySearchTests: XCTestCase {
    func testTranscriptHitSkipsIntelligenceWhenUnchecked() {
        let meeting = Meeting(title: "Campus Review")
        let segment = TranscriptSegment(
            speaker: .other("Jordan Hale"),
            text: "the 256 cabinet count is locked",
            startTime: 10,
            endTime: 12,
            isFinal: true
        )
        segment.meeting = meeting
        meeting.segments.append(segment)
        let insight = MeetingInsight(summary: "Discussed financing, not cabinets.")
        insight.meeting = meeting
        meeting.insights.append(insight)

        let transcriptOnly = LibrarySearch.search(
            query: "cabinet",
            in: [meeting],
            sources: .transcript
        )
        XCTAssertEqual(transcriptOnly.map(\.kind), [.transcript])
        XCTAssertEqual(transcriptOnly.first?.speakerName, "Jordan Hale")

        let intelOnly = LibrarySearch.search(
            query: "financing",
            in: [meeting],
            sources: .intelligence
        )
        XCTAssertEqual(intelOnly.map(\.kind), [.summary])
    }

    func testIntelligenceFindsActionsAndQuestions() {
        let meeting = Meeting(title: "Scope")
        let item = ActionItem(text: "Send the lender package")
        item.meeting = meeting
        meeting.actionItems.append(item)
        let insight = MeetingInsight(
            summary: "Short recap.",
            followUpQuestions: ["What is the First Nations engagement status?"],
            topics: ["North Campus"]
        )
        insight.meeting = meeting
        meeting.insights.append(insight)

        let hits = LibrarySearch.search(
            query: "lender",
            in: [meeting],
            sources: .intelligence
        )
        XCTAssertEqual(hits.map(\.kind), [.action])

        let topicHits = LibrarySearch.search(
            query: "North Campus",
            in: [meeting],
            sources: .intelligence
        )
        XCTAssertTrue(topicHits.contains { $0.kind == .topic })
    }

    func testEmptyQueryOrSourcesReturnsNothing() {
        let meeting = Meeting(title: "Empty")
        XCTAssertTrue(LibrarySearch.search(query: "  ", in: [meeting], sources: .both).isEmpty)
        XCTAssertTrue(LibrarySearch.search(query: "hello", in: [meeting], sources: []).isEmpty)
        var empty = LibrarySearchFilter()
        empty.sources = .both
        guard case .hits(let hits) = LibrarySearch.search(filter: empty, in: [meeting]) else {
            return XCTFail("expected hits")
        }
        XCTAssertTrue(hits.isEmpty)
    }

    func testSpeakerOnlyWithoutTextFindsMe() {
        let meeting = Meeting(title: "Campus")
        let mine = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "I will send the package",
            startTime: 0,
            endTime: 1,
            isFinal: true
        )
        let jordan = TranscriptSegment(
            speaker: .other("Jordan Hale"),
            text: "the package is ready",
            startTime: 1,
            endTime: 2,
            isFinal: true
        )
        mine.meeting = meeting
        jordan.meeting = meeting
        meeting.segments.append(contentsOf: [mine, jordan])

        var filter = LibrarySearchFilter()
        filter.speaker = "me"
        filter.sources = .transcript
        guard case .hits(let hits) = LibrarySearch.search(filter: filter, in: [meeting]) else {
            return XCTFail("expected hits")
        }
        XCTAssertEqual(hits.map(\.speakerName), ["Alex"])
    }

    func testSpeakerFilterKeepsOnlyThatVoice() {
        let meeting = Meeting(title: "Campus")
        let mine = TranscriptSegment(speaker: .meNamed("Alex"), text: "I will send the package", startTime: 0, endTime: 1, isFinal: true)
        let jordan = TranscriptSegment(speaker: .other("Jordan Hale"), text: "the package is ready", startTime: 1, endTime: 2, isFinal: true)
        mine.meeting = meeting
        jordan.meeting = meeting
        meeting.segments.append(contentsOf: [mine, jordan])

        var filter = LibrarySearchFilter()
        filter.text = "package"
        filter.speaker = "Jordan"
        filter.sources = .transcript
        guard case .hits(let hits) = LibrarySearch.search(filter: filter, in: [meeting]) else {
            return XCTFail("expected hits")
        }
        XCTAssertEqual(hits.map(\.speakerName), ["Jordan Hale"])
    }

    func testRegexFindsCabinetCount() {
        let meeting = Meeting(title: "Campus")
        let segment = TranscriptSegment(
            speaker: .other("Jordan Hale"),
            text: "the 256 cabinet count is locked",
            startTime: 0,
            endTime: 1,
            isFinal: true
        )
        segment.meeting = meeting
        meeting.segments.append(segment)

        var filter = LibrarySearchFilter()
        filter.text = #"cabinet.?count"#
        filter.useRegex = true
        filter.sources = .transcript
        guard case .hits(let hits) = LibrarySearch.search(filter: filter, in: [meeting]) else {
            return XCTFail("expected hits")
        }
        XCTAssertEqual(hits.count, 1)
    }

    func testInvalidRegexIsReported() {
        var filter = LibrarySearchFilter()
        filter.text = "(unterminated"
        filter.useRegex = true
        if case .invalidRegex = LibrarySearch.search(filter: filter, in: []) {
            return
        }
        XCTFail("expected invalidRegex")
    }

    func testMeetingNameAndDateFilters() {
        let early = Meeting(title: "Campus Review", date: Date(timeIntervalSince1970: 1_700_000_000))
        let late = Meeting(title: "Other Call", date: Date(timeIntervalSince1970: 1_800_000_000))
        var filter = LibrarySearchFilter()
        filter.meetingName = "Campus"
        filter.fromDate = Date(timeIntervalSince1970: 1_650_000_000)
        filter.toDate = Date(timeIntervalSince1970: 1_720_000_000)
        filter.sources = .intelligence
        filter.text = "Campus"
        guard case .hits(let hits) = LibrarySearch.search(filter: filter, in: [early, late]) else {
            return XCTFail("expected hits")
        }
        XCTAssertEqual(Set(hits.map(\.meetingTitle)), ["Campus Review"])
    }
}
