import XCTest
@testable import Grey_Eminence

final class TranscriptExportTests: XCTestCase {
    func testFilenameUsesFullTranscriptPattern() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        let name = TranscriptExportService.suggestedFilename(
            title: "North Campus Engineering Scope Review",
            date: date,
            duration: 47 * 60,
            fileExtension: "txt"
        )
        XCTAssertEqual(
            name,
            "North Campus Engineering Scope Review_20260818-47m-tr.txt"
        )
    }

    func testLinesSkipEmptyTextAndKeepSpeakerOrder() {
        let a = TranscriptSegment(speaker: .meNamed("Alex"), text: "  hello  ", startTime: 0, endTime: 1, isFinal: true)
        let blank = TranscriptSegment(speaker: .other("Pat"), text: "   ", startTime: 1, endTime: 2, isFinal: true)
        let b = TranscriptSegment(speaker: .other("Pat"), text: "there", startTime: 2, endTime: 3, isFinal: true)
        let lines = TranscriptExportService.lines(from: [b, blank, a])
        XCTAssertEqual(lines.map(\.speaker), ["Alex", "Pat"])
        XCTAssertEqual(lines.map(\.text), ["hello", "there"])
        XCTAssertEqual(lines.map(\.timestamp), ["0:00", "0:02"])
    }

    func testPlainTextAndCSVContainSpeakers() {
        let segment = TranscriptSegment(
            speaker: .other("Pat"),
            text: "First Nations?",
            startTime: 243,
            endTime: 248,
            isFinal: true
        )
        let lines = TranscriptExportService.lines(from: [segment])
        let text = TranscriptExportService.plainText(
            title: "Exec series",
            date: Date(timeIntervalSince1970: 1_787_000_000),
            durationLabel: "47:00",
            lines: lines
        )
        XCTAssertTrue(text.contains("Exec series"))
        XCTAssertTrue(text.contains("Pat"))
        XCTAssertTrue(text.contains("First Nations?"))

        let csv = TranscriptExportService.csv(lines: lines)
        XCTAssertTrue(csv.hasPrefix("Timestamp,Speaker,Text"))
        XCTAssertTrue(csv.contains("Pat"))
        XCTAssertTrue(csv.contains("4:03"))
    }
}
