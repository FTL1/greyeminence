import XCTest
@testable import Grey_Eminence

/// Locks the block parsing that turns an LLM's markdown answer into renderable
/// blocks (headings, lists, quotes, joined paragraphs).
final class MarkdownTextTests: XCTestCase {
    func testParsesHeadingsListsQuotesAndJoinedParagraphs() {
        let md = """
        ## Review Status

        Intro line one
        continues on the next line.

        - first point
        * second point
        1. step one
        2) step two

        > a quoted aside
        """
        let blocks = MarkdownBlock.parse(md)

        guard case .heading(let level, let title) = blocks[0] else { return XCTFail("expected heading") }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(title, "Review Status")

        // Two consecutive plain lines join into one paragraph.
        guard case .paragraph(let para) = blocks[1] else { return XCTFail("expected paragraph") }
        XCTAssertEqual(para, "Intro line one continues on the next line.")

        guard case .bullet(let b1) = blocks[2], b1 == "first point" else { return XCTFail("bullet -") }
        guard case .bullet(let b2) = blocks[3], b2 == "second point" else { return XCTFail("bullet *") }
        guard case .numbered(let m1, let n1) = blocks[4], m1 == "1.", n1 == "step one" else { return XCTFail("numbered .") }
        guard case .numbered(let m2, let n2) = blocks[5], m2 == "2.", n2 == "step two" else { return XCTFail("numbered )") }
        guard case .quote(let q) = blocks[6], q == "a quoted aside" else { return XCTFail("quote") }
    }

    func testInlineMarkersAndCitationsStayInBlockText() {
        // ** bold ** and [1] citations are left intact for inline rendering.
        let blocks = MarkdownBlock.parse("The **core** issue per [1] and [2].")
        guard case .paragraph(let p) = blocks.first else { return XCTFail("expected paragraph") }
        XCTAssertEqual(p, "The **core** issue per [1] and [2].")
    }

    func testHashWithoutSpaceIsNotAHeading() {
        // "#tag" is not a heading; should be a paragraph.
        let blocks = MarkdownBlock.parse("#notaheading here")
        guard case .paragraph = blocks.first else { return XCTFail("expected paragraph, not heading") }
    }
}
