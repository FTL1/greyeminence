import PDFKit
import XCTest
@testable import Grey_Eminence

/// The load-bearing question for the whole report feature: can a sandboxed
/// app drive `NSPrintOperation` to a PDF file, and does it actually paginate?
/// These run in the app test host, so they exercise the real sandbox.
@MainActor
final class ReportPDFRendererTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("report-pdf-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Enough paragraphs to overflow one Letter page several times over.
    private func longHTML(paragraphs: Int) -> String {
        let body = (1...paragraphs).map {
            "<p>Paragraph \($0). \(String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6))</p>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        @page { size: Letter; margin: 18mm; }
        body { font: 12pt/1.6 -apple-system, sans-serif; margin: 0; }
        </style></head><body>\(body)</body></html>
        """
    }

    func testWritesAPaginatedPDF() async throws {
        let url = scratch.appendingPathComponent("long.pdf")
        try await ReportPDFRenderer.writePDF(html: longHTML(paragraphs: 60), to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "no PDF was written")
        let document = try XCTUnwrap(PDFDocument(url: url), "the written file is not a readable PDF")
        XCTAssertGreaterThan(
            document.pageCount, 1,
            "content spanning many pages collapsed into \(document.pageCount) — pagination is not working"
        )
    }

    /// The page must come out Letter-sized. `createPDF` would produce one page
    /// as tall as the whole document, which is the failure mode this renderer
    /// exists to avoid.
    func testPagesAreLetterSized() async throws {
        let url = scratch.appendingPathComponent("sized.pdf")
        try await ReportPDFRenderer.writePDF(html: longHTML(paragraphs: 40), to: url)

        let document = try XCTUnwrap(PDFDocument(url: url))
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, ReportPDFRenderer.letter.width, accuracy: 2)
        XCTAssertEqual(bounds.height, ReportPDFRenderer.letter.height, accuracy: 2)
    }

    /// Text must survive as selectable text, not be rasterized — a report you
    /// cannot search or copy from is a screenshot with extra steps.
    func testTextIsExtractable() async throws {
        let url = scratch.appendingPathComponent("text.pdf")
        try await ReportPDFRenderer.writePDF(
            html: "<html><body><h1>Migration plan</h1><p>Distinctive marker phrase.</p></body></html>",
            to: url
        )

        let document = try XCTUnwrap(PDFDocument(url: url))
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Migration plan"), "heading missing from PDF text layer")
        XCTAssertTrue(text.contains("Distinctive marker phrase"), "body missing from PDF text layer")
    }

    /// Cross-references and the contents list are only useful if they arrive
    /// in the PDF as real link annotations. HTML that merely *looks* linked
    /// produces a document where nothing is clickable, with no other symptom.
    func testInternalLinksBecomeClickablePDFAnnotations() async throws {
        let url = scratch.appendingPathComponent("links.pdf")
        let filler = String(repeating: "<p>Filler to push the target onto a later page.</p>", count: 40)
        try await ReportPDFRenderer.writePDF(
            html: """
            <html><head><style>@page { size: Letter; margin: 18mm; }</style></head><body>
            <h1 id="section-0">Migration plan</h1>
            <p><a href="#figure-1">See Figure 1</a></p>
            \(filler)
            <figure id="figure-1"><figcaption><a href="#section-0">Back to Migration plan</a></figcaption></figure>
            </body></html>
            """,
            to: url
        )

        let document = try XCTUnwrap(PDFDocument(url: url))
        let links = (0..<document.pageCount)
            .compactMap { document.page(at: $0) }
            .flatMap(\.annotations)
            .filter { $0.action is PDFActionGoTo }
        XCTAssertEqual(links.count, 2, "expected a forward and a return link annotation")
    }

    /// Base64 data-URI images are how every figure reaches the page, so a
    /// failure here takes the entire figure feature with it.
    func testDataURIImageRenders() async throws {
        let url = scratch.appendingPathComponent("image.pdf")
        // 2x2 red PNG.
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVQIHWP8z8Dwn4EIwEREGVjZqIYBAFYgAQnhx6Y8AAAAAElFTkSuQmCC"
        try await ReportPDFRenderer.writePDF(
            html: """
            <html><body><img src="data:image/png;base64,\(png)" width="200" height="200"></body></html>
            """,
            to: url
        )

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        // A page carrying an embedded raster is meaningfully larger than an
        // empty one; this catches the image silently failing to decode.
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1_000, "PDF looks empty — the data-URI image probably did not render")
    }
}
