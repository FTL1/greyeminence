import XCTest
@testable import Grey_Eminence

final class IntelligenceExportTests: XCTestCase {
    private func sampleReport(includeTranscript: Bool = true) -> ReportModel {
        ReportModel(
            meta: .init(
                title: "North Campus Engineering Scope Review",
                date: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!,
                duration: "47m",
                durationMinutes: 47,
                attendees: ["Alex", "Pat"],
                sourceApp: "Microsoft Teams",
                generatedAt: Date(timeIntervalSince1970: 1_787_000_000)
            ),
            sections: [
                .init(
                    id: 0,
                    title: "Scope",
                    intro: "Campus engineering.",
                    points: [.init(label: "Budget", detail: "Hold the line.")],
                    figures: []
                )
            ],
            actionItems: [.init(text: "Send drawings", assignee: "Pat", isCompleted: false)],
            followUpQuestions: ["Who owns commissioning?"],
            topics: ["North Campus"],
            shareSessions: [],
            transcript: includeTranscript
                ? [.init(speaker: "Alex", formattedTimestamp: "0:12", text: "Let's start.")]
                : []
        )
    }

    func testSelectionDropsUncheckedParts() {
        var selection = IntelligenceExportSelection()
        selection.includeSummary = false
        selection.includeActionItems = false
        selection.includeQuestions = true
        selection.includeTopics = false
        selection.includeSharedScreens = false
        selection.includeTranscript = true
        let filtered = selection.applying(to: sampleReport())
        XCTAssertTrue(filtered.sections.isEmpty)
        XCTAssertTrue(filtered.actionItems.isEmpty)
        XCTAssertEqual(filtered.followUpQuestions, ["Who owns commissioning?"])
        XCTAssertTrue(filtered.topics.isEmpty)
        XCTAssertEqual(filtered.transcript.count, 1)
        XCTAssertFalse(filtered.isEmpty)
    }

    func testAllSectionsToggle() {
        var selection = IntelligenceExportSelection()
        selection.includeAllSections = false
        XCTAssertFalse(selection.includeSummary)
        XCTAssertFalse(selection.includeActionItems)
        selection.includeAllSections = true
        XCTAssertTrue(selection.includeTopics)
        XCTAssertTrue(selection.includeSharedScreens)
    }

    func testMarkdownAndCSVIncludeSelectedContent() {
        let report = sampleReport()
        let md = IntelligenceExport.markdown(report)
        XCTAssertTrue(md.contains("# North Campus Engineering Scope Review"))
        XCTAssertTrue(md.contains("Send drawings"))
        XCTAssertTrue(md.contains("Let's start."))
        XCTAssertTrue(md.contains("North Campus"))

        let csv = IntelligenceExport.csv(report)
        XCTAssertTrue(csv.contains("Action"))
        XCTAssertTrue(csv.contains("Send drawings"))
        XCTAssertTrue(csv.contains("Transcript"))
        XCTAssertTrue(csv.contains("Alex"))
    }

    func testJSONContainsKeys() throws {
        let data = try IntelligenceExport.json(sampleReport())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["title"] as? String, "North Campus Engineering Scope Review")
        XCTAssertEqual((object?["topics"] as? [String])?.first, "North Campus")
        XCTAssertEqual((object?["transcript"] as? [[String: Any]])?.count, 1)
    }

    func testDocxAndXlsxAreZips() {
        let report = sampleReport()
        let docx = IntelligenceExport.docx(report)
        XCTAssertEqual(Array(docx.prefix(2)), [0x50, 0x4b], "docx must be a zip")
        XCTAssertGreaterThan(docx.count, 200)

        let xlsx = IntelligenceExport.xlsx(report)
        XCTAssertEqual(Array(xlsx.prefix(2)), [0x50, 0x4b], "xlsx must be a zip")
        XCTAssertGreaterThan(xlsx.count, 200)
    }

    func testTranscriptOnlyReportIsNotEmpty() {
        var selection = IntelligenceExportSelection()
        selection.includeAllSections = false
        selection.includeTranscript = true
        let filtered = selection.applying(to: sampleReport())
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.sections.isEmpty)
        XCTAssertEqual(filtered.transcript.first?.text, "Let's start.")
    }
}
