import XCTest
@testable import Grey_Eminence

/// Pure tests for the pasteboard formatter. Pasting a summary into Teams
/// produced a wall of flat text with literal bullet and numbering
/// characters; these cover the markup that replaces it.
final class RichClipboardTests: XCTestCase {

    private let sections = [
        SummarySection(
            title: "Messages vs tasks distinction",
            intro: "Matt argued that not every message should spawn a task.",
            points: [
                SummaryPoint(label: "Task should represent real work", detail: "A task should exist when there is work."),
                SummaryPoint(label: "Simple replies shouldn't create tasks", detail: "A follow-on action should."),
            ]
        )
    ]

    func testSummaryHTMLUsesRealStructure() {
        let html = RichClipboard.summaryHTML(sections)

        XCTAssertTrue(html.contains("<b>1. Messages vs tasks distinction</b>"), "the heading should be numbered and bold")
        XCTAssertTrue(html.contains("<ul>"), "points should be a real list, not bullet characters")
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 2)
        XCTAssertTrue(html.contains("<b>Task should represent real work</b>"))
        XCTAssertFalse(html.contains("•"), "a literal bullet glyph means it is not a list")
    }

    /// Teams drops anything beyond a narrow subset, so cleverer markup either
    /// vanishes or arrives mangled.
    func testSummaryHTMLStaysWithinTheTagsTeamsKeeps() {
        let html = RichClipboard.summaryHTML(sections)
        for banned in ["<h1", "<h2", "<div", "style=", "class=", "<table"] {
            XCTAssertFalse(html.contains(banned), "\(banned) will not survive a paste into Teams")
        }
    }

    /// Summary text is model output and can contain anything.
    func testUserContentIsEscaped() {
        let hostile = [
            SummarySection(
                title: "A < B & C",
                intro: "<script>alert(1)</script>",
                points: [SummaryPoint(label: "x > y", detail: "5 & 6")]
            )
        ]
        let html = RichClipboard.summaryHTML(hostile)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("A &lt; B &amp; C"))
        XCTAssertTrue(html.contains("x &gt; y"))
        XCTAssertTrue(html.contains("5 &amp; 6"))
    }

    /// Ampersand must be escaped first or it re-escapes the entities the
    /// other replacements produce.
    func testAmpersandIsNotDoubleEscaped() {
        XCTAssertEqual(RichClipboard.escape("<a & b>"), "&lt;a &amp; b&gt;")
    }

    /// The plain flavour is what receivers without HTML get, so it has to
    /// stand on its own rather than be a stripped-back afterthought.
    func testPlainTextRemainsReadable() {
        let plain = RichClipboard.summaryPlainText(sections)
        XCTAssertTrue(plain.hasPrefix("1. Messages vs tasks distinction"))
        XCTAssertTrue(plain.contains("• Task should represent real work: A task should exist"))
        XCTAssertFalse(plain.contains("<"), "the plain flavour must carry no markup")
    }

    func testEmptyLabelOrDetailDoesNotLeaveADanglingSeparator() {
        let sparse = [
            SummarySection(title: "T", intro: nil, points: [
                SummaryPoint(label: "", detail: "detail only"),
                SummaryPoint(label: "label only", detail: ""),
            ])
        ]
        let html = RichClipboard.summaryHTML(sparse)
        XCTAssertTrue(html.contains("<li>detail only</li>"))
        XCTAssertTrue(html.contains("<li><b>label only</b></li>"))
        XCTAssertFalse(html.contains("—</li>"), "a separator with nothing after it")
        XCTAssertFalse(html.contains("<b></b>"))
    }

    func testSectionWithoutPointsEmitsNoEmptyList() {
        let bare = [SummarySection(title: "Just a heading", intro: "and prose", points: [])]
        let html = RichClipboard.summaryHTML(bare)
        XCTAssertFalse(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<p>and prose</p>"))
    }
}
