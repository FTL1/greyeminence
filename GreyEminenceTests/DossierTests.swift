import XCTest
import SwiftData
@testable import Grey_Eminence

final class DossierTests: XCTestCase {
    func testNamesMatchIgnoresCaseAndExtraWords() {
        XCTAssertTrue(DossierNaming.namesMatch("Jordan", "Jordan V"))
        XCTAssertTrue(DossierNaming.namesMatch("Alex Morgan", "Alex"))
        XCTAssertFalse(DossierNaming.namesMatch("Jordan", "Sam"))
    }

    func testFilterActionsByAudience() {
        let items = [
            DossierAction(text: "Fix the ROM", assignee: "Me", isCompleted: false, sourceQuote: "I'll update the ROM"),
            DossierAction(text: "Send drawings", assignee: "Jordan", isCompleted: false, sourceQuote: "I can send the drawings"),
            DossierAction(text: "Unowned", assignee: nil, isCompleted: false, sourceQuote: nil),
        ]
        let mine = DossierFacts.filterActions(items, audience: .me, myLabels: ["Alex", "Me"])
        XCTAssertEqual(mine.map(\.text), ["Fix the ROM", "Unowned"])

        let jordan = DossierFacts.filterActions(items, audience: .person("Jordan"), myLabels: ["Alex"])
        XCTAssertEqual(jordan.map(\.text), ["Send drawings"])

        let boss = DossierFacts.filterActions(items, audience: .boss, myLabels: ["Alex"])
        XCTAssertEqual(boss.count, 3)
    }

    func testBriefCapsLists() {
        let many = (1...10).map { "q\($0)" }
        XCTAssertEqual(DossierFacts.capList(many, depth: .brief).count, 5)
        XCTAssertEqual(DossierFacts.capList(many, depth: .detailed).count, 10)
    }

    func testPromptForbidsHallucinationAndDoesNotInvent() throws {
        let snap = sampleSnapshot()
        let prompt = DossierPromptPackage.promptMarkdown(
            snapshots: [snap],
            audience: .me,
            includeTranscript: false
        )
        let lower = prompt.lowercased()
        XCTAssertTrue(lower.contains("do not hallucinate"))
        XCTAssertTrue(lower.contains("do not invent"))
        XCTAssertTrue(lower.contains("meeting.json"))
        XCTAssertTrue(prompt.contains("Align prospect docs"))
        XCTAssertFalse(prompt.contains("financing status unless"))

        let json = try DossierPromptPackage.jsonData(
            snapshots: [snap],
            audience: .me,
            includeTranscript: false
        )
        let text = String(data: json, encoding: .utf8)!
        XCTAssertTrue(text.contains("do_not_invent"))
        XCTAssertTrue(text.contains("Fix the ROM"))
        XCTAssertTrue(text.contains("I'll update the ROM"))
        XCTAssertFalse(text.contains("First Nations"))
        XCTAssertFalse(text.contains("\"transcript\""))
    }

    func testRendererOnlyEmitsStoredStrings() {
        let snap = sampleSnapshot()
        let blocks = DossierRenderer.blocks(
            snapshots: [snap],
            audience: .person("Jordan"),
            depth: .brief,
            includeTranscript: false
        )
        let md = DossierRenderer.markdown(blocks)
        XCTAssertTrue(md.contains("Send drawings"))
        XCTAssertFalse(md.contains("Fix the ROM"))
        XCTAssertTrue(md.contains("does not add facts"))
        XCTAssertFalse(md.contains("environmental"))
    }

    func testOnePagerSlug() {
        XCTAssertEqual(DossierNaming.slug("Jordan V."), "jordan-v")
        XCTAssertEqual(DossierAudience.person("Guest-1").fileSlug, "guest-1")
    }

    @MainActor
    func testRelatedMeetingsUseSeriesID() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let series = UUID()
        let a = Meeting(title: "Call 1")
        a.seriesID = series
        a.seriesTitle = "North Campus"
        let b = Meeting(title: "Call 2")
        b.seriesID = series
        b.seriesTitle = "North Campus"
        let other = Meeting(title: "Unrelated")
        context.insert(a)
        context.insert(b)
        context.insert(other)
        let related = DossierFacts.relatedMeetings(to: a, library: [a, b, other])
        XCTAssertEqual(Set(related.map(\.id)), Set([a.id, b.id]))
    }

    private func sampleSnapshot() -> DossierMeetingSnapshot {
        DossierMeetingSnapshot(
            id: UUID(),
            title: "North Campus Engineering Scope Review",
            generatedTitle: "Align prospect docs",
            date: Date(timeIntervalSince1970: 1_787_000_000),
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
}
