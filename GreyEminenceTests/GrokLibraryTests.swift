import XCTest
@testable import Grey_Eminence

final class GrokLibraryTests: XCTestCase {
    func testWritesTranscriptIntelAndIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-lib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snap = sampleSnapshot()
        let record = GrokLibrary.writeSnapshot(snap, series: "Weekly Standup", into: root)
        XCTAssertEqual(record.series, "Weekly Standup")
        XCTAssertTrue(record.hasTranscript)
        XCTAssertEqual(record.actionCount, 2)
        XCTAssertEqual(record.openActionCount, 2)

        let folder = root.appendingPathComponent("meetings/\(snap.id.uuidString)", isDirectory: true)
        let transcript = try String(
            contentsOf: folder.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        XCTAssertTrue(transcript.contains("25 megawatts"))
        XCTAssertTrue(transcript.contains("I'll update the ROM"))
        let intel = try String(
            contentsOf: folder.appendingPathComponent("intel.md"),
            encoding: .utf8
        )
        XCTAssertTrue(intel.contains("Send drawings") || intel.contains("ROM") || intel.contains("Documents"))

        GrokLibrary.writeIndex([record], into: root)
        let data = try Data(contentsOf: root.appendingPathComponent("index.json"))
        let index = try JSONDecoder().decode(GrokLibrary.Index.self, from: data)
        XCTAssertEqual(index.meetingCount, 1)
        XCTAssertEqual(index.meetings.first?.id, snap.id.uuidString)
        XCTAssertEqual(index.bundleID, "com.ftl1.greyeminence")
    }

    func testSkipsEmptySeries() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-lib-\(UUID().uuidString)", isDirectory: true)
        let record = GrokLibrary.writeSnapshot(sampleSnapshot(), series: "  ", into: root)
        XCTAssertNil(record.series)
        try? FileManager.default.removeItem(at: root)
    }

    private func sampleSnapshot() -> DossierMeetingSnapshot {
        DossierMeetingSnapshot(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "Weekly Standup",
            generatedTitle: "Align ROM numbers",
            date: date(2026, 8, 18),
            durationLabel: "47m",
            durationMinutes: 47,
            attendees: ["Alex", "Jordan"],
            speakers: ["Alex", "Jordan"],
            myLabels: ["Alex", "Me"],
            summaryJSON: """
            [{"title":"Documents","intro":"Alex is correcting outbound scope language.","points":[{"label":"ROM","detail":"Update numbers Jordan voiced."}]}]
            """,
            actionItems: [
                DossierAction(text: "Fix the ROM", assignee: "Me", isCompleted: false, sourceQuote: "I'll update the ROM"),
                DossierAction(text: "Send drawings", assignee: "Jordan", isCompleted: false, sourceQuote: "I can send the drawings"),
            ],
            followUps: ["Does the write-up use Jordan's 25MW figure?"],
            topics: ["prospect documents", "ROM"],
            shareNarratives: [],
            transcript: [
                DossierLine(speaker: "Jordan", timestamp: "0:12", text: "It is 25 megawatts not 40.", isMe: false),
                DossierLine(speaker: "Alex", timestamp: "0:20", text: "I'll update the ROM.", isMe: true),
            ]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
