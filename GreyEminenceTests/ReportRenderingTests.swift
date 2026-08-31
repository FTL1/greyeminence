import XCTest
@testable import Grey_Eminence

/// Pure tests for the report pipeline downstream of the builder — no
/// SwiftData, no AppKit, no app host state.
final class ReportRenderingTests: XCTestCase {

    // MARK: - Fixtures

    private func figure(caption: String, at time: TimeInterval = 62) -> ReportModel.Figure {
        ReportModel.Figure(
            id: UUID(),
            timestamp: time,
            formattedTimestamp: ReportModelBuilder.timestampLabel(time),
            caption: caption,
            imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            windowTitle: "Keynote"
        )
    }

    private func report(
        sections: [ReportModel.Section] = [],
        actionItems: [ReportModel.ActionItem] = [],
        followUps: [String] = [],
        shareSessions: [ReportModel.ShareSession] = [],
        transcript: [ReportModel.TranscriptLine] = []
    ) -> ReportModel {
        ReportModel(
            meta: .init(
                title: "Architecture Braintrust",
                date: Date(timeIntervalSince1970: 1_777_000_000),
                duration: "48m",
                attendees: ["Ada Lovelace", "Grace Hopper"],
                sourceApp: "Zoom",
                generatedAt: Date(timeIntervalSince1970: 1_777_003_000)
            ),
            sections: sections,
            actionItems: actionItems,
            followUpQuestions: followUps,
            topics: [],
            shareSessions: shareSessions,
            transcript: transcript
        )
    }

    // MARK: - Escaping

    /// Meeting titles, OCR text and transcripts are arbitrary user content.
    /// A stray angle bracket must never become markup.
    func testUserContentIsEscaped() {
        let html = ReportHTMLRenderer.render(
            report(sections: [
                .init(id: 0, title: "<script>alert(1)</script>", intro: "a & b", points: [], figures: [])
            ]),
            template: ReportTemplateCatalog.plain
        )
        XCTAssertFalse(html.contains("<script>"), "raw script tag survived escaping")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("a &amp; b"))
    }

    /// Ampersand must be escaped first, or the other replacements get
    /// double-escaped into `&amp;lt;`.
    func testAmpersandIsNotDoubleEscaped() {
        XCTAssertEqual(ReportHTMLRenderer.escape("<a & b>"), "&lt;a &amp; b&gt;")
    }

    // MARK: - Self-containment

    /// The artifact must never phone home — no CDN fonts, no remote logos.
    /// This is what makes the same HTML safe to hand to a PDF renderer, a
    /// preview, and a future upload.
    func testRenderedDocumentReferencesNoRemoteHosts() {
        let html = ReportHTMLRenderer.render(
            report(
                sections: [.init(id: 0, title: "Plan", intro: nil, points: [], figures: [figure(caption: "diff")])],
                shareSessions: []
            ),
            template: ReportTemplateCatalog.plain
        )
        XCTAssertFalse(html.contains("http://"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertTrue(html.contains("data:image/jpeg;base64,"))
    }

    /// The contents list is an `<ol>` numbered by a CSS counter. A reset that
    /// only covers `ul` leaves the native marker on and prints both numbers
    /// — "1. 1. AI-first…".
    func testListMarkersAreSuppressedForOrderedListsToo() {
        for template in ReportTemplateCatalog.all {
            XCTAssertTrue(
                template.css.contains("ul, ol") || template.css.contains("ol,"),
                "\(template.id) does not reset ordered-list markers, so numbers will double up"
            )
        }
    }

    /// Dropping the first page's top margin is only safe for a template whose
    /// header paints a full-bleed band. On one whose header is plain text it
    /// puts the title flush against the paper edge.
    func testFlushMastheadOnlyUsedByTemplatesThatPaintABand() {
        for template in ReportTemplateCatalog.all where template.css.contains("@page :first") {
            guard let headerRule = template.css.range(of: ".ge-header {") else {
                XCTFail("\(template.id) drops the top margin but styles no header")
                continue
            }
            let block = template.css[headerRule.lowerBound...].prefix(400)
            XCTAssertTrue(
                block.contains("background:"),
                "\(template.id) drops the top margin without a masthead to fill it"
            )
        }
    }

    func testEveryBuiltInTemplateIsSelfContained() {
        for template in ReportTemplateCatalog.all {
            XCTAssertFalse(template.css.isEmpty, "\(template.id) has no CSS")
            XCTAssertFalse(template.css.contains("http://"), "\(template.id) references a remote host")
            XCTAssertFalse(template.css.contains("https://"), "\(template.id) references a remote host")
            XCTAssertTrue(
                template.css.contains("break-inside: avoid"),
                "\(template.id) lets figures split away from their captions"
            )
        }
    }

    // MARK: - Figure numbering

    /// Numbering must run in reading order and continue across the appendix,
    /// or "Figure 3" in the text points at the wrong picture.
    func testFiguresAreNumberedInReadingOrderAcrossSections() {
        let html = ReportHTMLRenderer.render(
            report(
                sections: [
                    .init(id: 0, title: "One", intro: nil, points: [], figures: [figure(caption: "first")]),
                    .init(id: 1, title: "Two", intro: nil, points: [], figures: [figure(caption: "second")]),
                ],
                shareSessions: [
                    .init(
                        id: UUID(), windowTitle: "Keynote", startLabel: "1:00", endLabel: "5:00",
                        narrative: "A walkthrough.", keyMoments: [],
                        figures: [figure(caption: "third")]
                    )
                ]
            ),
            template: ReportTemplateCatalog.plain
        )
        let order = ["Figure 1", "Figure 2", "Figure 3"].map { html.range(of: $0)?.lowerBound }
        XCTAssertFalse(order.contains(where: { $0 == nil }), "a figure number is missing")
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted())
    }

    // MARK: - Cross-links
    //
    // These become real PDF link annotations, so a broken anchor is a dead
    // link in the exported document with no other visible symptom.

    /// A screenshot printed in the appendix must be reachable from the
    /// section it evidences, and must lead back to it.
    func testAppendixFigureIsCrossLinkedWithItsSection() {
        var anchored = figure(caption: "schema diff")
        anchored.sectionIndex = 1
        anchored.sectionTitle = "Q3 risks"

        let html = ReportHTMLRenderer.render(
            report(
                sections: [
                    .init(id: 0, title: "Migration plan", intro: nil, points: [], figures: []),
                    .init(id: 1, title: "Q3 risks", intro: nil, points: [], figures: []),
                ],
                shareSessions: [
                    .init(
                        id: UUID(), windowTitle: "Keynote", startLabel: "0:00", endLabel: "9:00",
                        narrative: "A walkthrough.", keyMoments: [], figures: [anchored]
                    )
                ]
            ),
            template: ReportTemplateCatalog.plain
        )

        let sectionAnchor = ReportHTMLRenderer.sectionAnchor(1)
        let figureAnchor = ReportHTMLRenderer.figureAnchor(anchored)

        XCTAssertTrue(html.contains("id=\"\(sectionAnchor)\""), "section is not a link target")
        XCTAssertTrue(html.contains("id=\"\(figureAnchor)\""), "figure is not a link target")
        XCTAssertTrue(html.contains("href=\"#\(figureAnchor)\""), "section does not link to the figure")
        XCTAssertTrue(html.contains("href=\"#\(sectionAnchor)\""), "figure does not link back")
        XCTAssertTrue(html.contains("Q3 risks"), "the back link should name the section")
    }

    /// Every `href="#…"` must have a matching `id="…"`, or the PDF carries a
    /// link annotation that goes nowhere.
    func testEveryInternalLinkHasATarget() {
        var anchored = figure(caption: "diff")
        anchored.sectionIndex = 0
        anchored.sectionTitle = "Migration plan"

        for template in ReportTemplateCatalog.all {
            let html = ReportHTMLRenderer.render(
                report(
                    sections: [.init(id: 0, title: "Migration plan", intro: nil, points: [], figures: [])],
                    shareSessions: [
                        .init(
                            id: UUID(), windowTitle: nil, startLabel: "0:00", endLabel: "1:00",
                            narrative: "n", keyMoments: [], figures: [anchored]
                        )
                    ]
                ),
                template: template
            )
            let targets = Set(matches(in: html, pattern: #"id="([^"]+)""#))
            for reference in matches(in: html, pattern: ##"href="#([^"]+)""##) {
                XCTAssertTrue(
                    targets.contains(reference),
                    "\(template.id): link to #\(reference) has no matching id"
                )
            }
        }
    }

    /// An unanchored screenshot has no section to return to, so it must not
    /// emit a dangling back-link.
    func testUnanchoredFigureHasNoBackLink() {
        let html = ReportHTMLRenderer.render(
            report(
                sections: [.init(id: 0, title: "Plan", intro: nil, points: [], figures: [])],
                shareSessions: [
                    .init(
                        id: UUID(), windowTitle: nil, startLabel: "0:00", endLabel: "1:00",
                        narrative: "n", keyMoments: [], figures: [figure(caption: "unclaimed")]
                    )
                ]
            ),
            template: ReportTemplateCatalog.plain
        )
        // Markup, not bare class names — every stylesheet defines rules for
        // both of these whether or not anything emits them.
        XCTAssertFalse(html.contains("class=\"ge-figure-back\""))
        XCTAssertFalse(html.contains("<p class=\"ge-figure-refs\">"))
    }

    private func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Open questions placement

    /// Given the same heading treatment as the summary, open questions read
    /// as one more of its sections. They lead the document and use the
    /// callout styling instead.
    func testOpenQuestionsLeadTheDocumentAndAreNotStyledAsASection() {
        let html = ReportHTMLRenderer.render(
            report(
                sections: [
                    .init(id: 0, title: "Messages vs tasks", intro: nil, points: [], figures: []),
                    .init(id: 1, title: "Document service", intro: nil, points: [], figures: []),
                ],
                actionItems: [.init(text: "Ship it", assignee: nil, isCompleted: false)],
                followUps: ["What are the reporting requirements?"]
            ),
            template: ReportTemplateCatalog.plain
        )

        let questions = try! XCTUnwrap(html.range(of: "id=\"ge-followups\""))
        let firstSection = try! XCTUnwrap(html.range(of: "id=\"\(ReportHTMLRenderer.sectionAnchor(0))\""))
        let actions = try! XCTUnwrap(html.range(of: "id=\"ge-actions\""))

        XCTAssertLessThan(questions.lowerBound, firstSection.lowerBound, "open questions should come before the summary")
        XCTAssertLessThan(firstSection.lowerBound, actions.lowerBound, "action items should still come last")

        XCTAssertTrue(html.contains("<section class=\"ge-callout ge-followups\""))
        XCTAssertTrue(html.contains("<h2 class=\"ge-callout-title\">Open questions</h2>"))
        XCTAssertFalse(
            html.contains("ge-section ge-followups"),
            "reusing the section class is what made it look like part of the summary"
        )
    }

    /// The contents list has to follow document order or it misdirects.
    func testContentsListsOpenQuestionsFirst() {
        var template = ReportTemplateCatalog.plain
        template.includesTableOfContents = true
        let html = ReportHTMLRenderer.render(
            report(
                sections: [.init(id: 0, title: "Messages vs tasks", intro: nil, points: [], figures: [])],
                followUps: ["A question?"]
            ),
            template: template
        )
        // Anchor on the markup: the stylesheet also contains "ge-toc-list",
        // and matching that would start the window inside the CSS.
        let toc = String(html[html.range(of: "<ol class=\"ge-toc-list\">")!.lowerBound...].prefix(400))
        let questions = try! XCTUnwrap(toc.range(of: "Open questions"))
        let section = try! XCTUnwrap(toc.range(of: "Messages vs tasks"))
        XCTAssertLessThan(questions.lowerBound, section.lowerBound)
    }

    func testEveryTemplateStylesTheCallout() {
        for template in ReportTemplateCatalog.all {
            XCTAssertTrue(
                template.css.contains(".ge-callout-title"),
                "\(template.id) leaves open questions unstyled, so they fall back to looking like body text"
            )
        }
    }

    // MARK: - Table of contents

    func testTableOfContentsListsEverySectionAndBlock() {
        var template = ReportTemplateCatalog.plain
        template.includesTableOfContents = true

        let html = ReportHTMLRenderer.render(
            report(
                sections: [
                    .init(id: 0, title: "Migration plan", intro: nil, points: [], figures: []),
                    .init(id: 1, title: "Q3 risks", intro: nil, points: [], figures: []),
                ],
                actionItems: [.init(text: "Ship it", assignee: nil, isCompleted: false)],
                followUps: ["What about latency?"]
            ),
            template: template
        )

        XCTAssertTrue(html.contains("<ol class=\"ge-toc-list\">"))
        XCTAssertTrue(html.contains("href=\"#\(ReportHTMLRenderer.sectionAnchor(0))\""))
        XCTAssertTrue(html.contains("href=\"#\(ReportHTMLRenderer.sectionAnchor(1))\""))
        XCTAssertTrue(html.contains("href=\"#ge-actions\""))
        XCTAssertTrue(html.contains("href=\"#ge-followups\""))
    }

    /// The contents must not advertise a block the template is not printing —
    /// that would be a link to nothing.
    func testTableOfContentsOmitsBlocksTheTemplateExcludes() {
        var template = ReportTemplateCatalog.plain
        template.includesTableOfContents = true
        template.includesActionItems = false

        let html = ReportHTMLRenderer.render(
            report(
                sections: [
                    .init(id: 0, title: "One", intro: nil, points: [], figures: []),
                    .init(id: 1, title: "Two", intro: nil, points: [], figures: []),
                ],
                actionItems: [.init(text: "Ship it", assignee: nil, isCompleted: false)]
            ),
            template: template
        )
        XCTAssertFalse(html.contains("href=\"#ge-actions\""))
    }

    /// A contents list with one entry is a redundant heading, not navigation.
    func testTableOfContentsSuppressedWhenThereIsOnlyOneEntry() {
        var template = ReportTemplateCatalog.plain
        template.includesTableOfContents = true
        let html = ReportHTMLRenderer.render(
            report(sections: [.init(id: 0, title: "Only", intro: nil, points: [], figures: [])]),
            template: template
        )
        XCTAssertFalse(html.contains("<ol class=\"ge-toc-list\">"))
    }

    /// Page-per-section left too much white space on real reports, so no
    /// built-in applies it. The rule survives for templates that want it.
    func testNoBuiltInBreaksEverySectionOntoItsOwnPage() {
        for template in ReportTemplateCatalog.all {
            XCTAssertFalse(
                template.css.contains(".ge-section { break-before: page"),
                "\(template.id) puts every section on its own page"
            )
        }
        XCTAssertTrue(ReportTemplateCatalog.sectionPageBreaks.contains("break-before: page"))
    }

    // MARK: - Template switches

    func testFiguresOmittedWhenTemplateExcludesThem() {
        var template = ReportTemplateCatalog.plain
        template.includesFigures = false
        let html = ReportHTMLRenderer.render(
            report(sections: [
                .init(id: 0, title: "Plan", intro: nil, points: [], figures: [figure(caption: "diff")])
            ]),
            template: template
        )
        // Assert on markup, not the bare class name — the stylesheet always
        // carries `.ge-figure` rules whether or not a figure is emitted.
        XCTAssertFalse(html.contains("<figure class=\"ge-figure\""))
        XCTAssertFalse(html.contains("data:image/jpeg"))
        XCTAssertTrue(html.contains("Plan"), "excluding figures must not drop the section")
    }

    func testTranscriptOnlyAppearsWhenRequested() {
        let lines = [ReportModel.TranscriptLine(speaker: "Ada", formattedTimestamp: "0:05", text: "Morning.")]
        let plain = ReportHTMLRenderer.render(report(transcript: lines), template: ReportTemplateCatalog.plain)
        XCTAssertFalse(plain.contains("ge-transcript"), "Plain must not carry a transcript by default")

        var verbose = ReportTemplateCatalog.plain
        verbose.includesTranscript = true
        let full = ReportHTMLRenderer.render(report(transcript: lines), template: verbose)
        XCTAssertTrue(full.contains("ge-transcript"))
        XCTAssertTrue(full.contains("Morning."))
    }

    /// A completed action must be visually distinguishable, not silently
    /// rendered the same as an open one.
    func testCompletedActionItemsCarryTheirOwnClass() {
        let html = ReportHTMLRenderer.render(
            report(actionItems: [
                .init(text: "Ship the migration", assignee: "Ada", isCompleted: true),
                .init(text: "Draft the RFC", assignee: nil, isCompleted: false),
            ]),
            template: ReportTemplateCatalog.plain
        )
        XCTAssertTrue(html.contains("ge-action-done"))
        XCTAssertTrue(html.contains("ge-action-open"))
        XCTAssertTrue(html.contains("Ada"))
    }

    // MARK: - Representative frame selection
    //
    // Regression cover for a report that exported with no pictures at all:
    // sessions whose synthesis pass never ran have no key moments, and the
    // fallback has to carry them.

    @MainActor
    func testRepresentativeFramesSpanTheWholeSessionInOrder() {
        let frames = (0..<20).map { makeFrame(sequence: $0, observation: "obs \($0)") }
        let picked = ReportModelBuilder.representativeFrames(from: frames, limit: 4)

        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(picked.map(\.sequence), picked.map(\.sequence).sorted())
        // One from each quarter of the session — coverage of its arc, even
        // though which frame within a quarter wins is a quality decision.
        XCTAssertLessThan(picked[0].sequence, 5)
        XCTAssertGreaterThanOrEqual(picked[3].sequence, 15)
    }

    /// The reported problem: every chosen screenshot was a gallery of faces.
    /// Content must beat proximity when both are on offer.
    @MainActor
    func testContentFramesBeatVideoFramesInTheSameBucket() {
        var frames: [ScreenShareFrame] = []
        for index in 0..<8 {
            let frame = makeFrame(sequence: index, observation: "obs")
            // Odd frames are the shared slide, even ones the camera feed.
            frame.contentType = index.isMultiple(of: 2) ? .video : .slide
            frame.ocrText = index.isMultiple(of: 2) ? "" : String(repeating: "agenda text ", count: 40)
            frames.append(frame)
        }
        let picked = ReportModelBuilder.representativeFrames(from: frames, limit: 4)
        XCTAssertEqual(picked.count, 4)
        XCTAssertTrue(
            picked.allSatisfy { $0.contentType == .slide },
            "picked \(picked.map { ($0.sequence, $0.contentType?.rawValue ?? "nil") })"
        )
    }

    /// The picker and the builder must number sections identically, or a
    /// legacy flat-string summary is ticked in one place and dropped in
    /// another.
    @MainActor
    func testPickerTitlesMatchTheBuiltReportSections() {
        let meeting = Meeting(title: "Sync", date: .now, duration: 600, status: .completed)
        let insight = MeetingInsight(summary: "A legacy flat summary with no JSON structure at all.")
        meeting.insights = [insight]

        let titles = ReportModelBuilder.sectionTitles(for: meeting)
        let built = ReportModelBuilder.build(from: meeting)
        XCTAssertEqual(titles.map(\.id), built.sections.map(\.id))
        XCTAssertEqual(titles.map(\.title), built.sections.map(\.title))
    }

    // MARK: - Report title
    //
    // The report must be titled whatever the meeting is called when you
    // export it. `generatedTitle` is a stash the app only promotes into
    // `title` for meetings that aren't calendar-linked, so reading it
    // directly exports under a name the app never shows.

    @MainActor
    func testReportUsesTheMeetingsVisibleTitleNotTheGeneratedOne() {
        let meeting = Meeting(title: "Weekly Architecture Sync", date: .now, duration: 1800, status: .completed)
        meeting.generatedTitle = "Discussion of Database Migration Strategy"

        let report = ReportModelBuilder.build(from: meeting)
        XCTAssertEqual(report.meta.title, "Weekly Architecture Sync")
    }

    /// Renaming a meeting must change what the next export is called.
    @MainActor
    func testRenamingTheMeetingChangesTheExportedFilename() {
        let meeting = Meeting(title: "Untitled", date: .now, duration: 600, status: .completed)
        meeting.generatedTitle = "Some AI Name"
        meeting.title = "Vendor call — Acme"

        let report = ReportModelBuilder.build(from: meeting)
        let name = ReportExportService.suggestedFilename(
            for: report.meta,
            template: ReportTemplateCatalog.plain
        )
        XCTAssertTrue(name.hasPrefix("Vendor call — Acme_"), "got \(name)")
        XCTAssertTrue(name.hasSuffix("-10m-intel.pdf"), "duration 600s should be 10 minutes, got \(name)")
        XCTAssertFalse(name.contains("Some AI Name"))
    }

    // MARK: - Caption fallback
    //
    // `observation` is a 100–250 word paragraph from the vision pass. Printed
    // raw under a screenshot it is a wall of text.

    @MainActor
    func testLongObservationBecomesAShortCaption() {
        let frame = makeFrame(
            sequence: 0,
            observation: "The slide shows the Q3 migration timeline. " + String(repeating: "Further detail follows. ", count: 40)
        )
        let caption = ReportModelBuilder.shortCaption(for: frame)

        XCTAssertLessThanOrEqual(caption.count, ReportModelBuilder.captionCap + 1)
        XCTAssertTrue(caption.hasPrefix("The slide shows the Q3 migration timeline"))
        XCTAssertFalse(caption.contains("Further detail follows"), "took more than the first sentence")
    }

    /// A first "sentence" that is really an abbreviation must not produce a
    /// two-word caption.
    @MainActor
    func testVeryShortFirstSentenceIsNotUsedAlone() {
        let frame = makeFrame(
            sequence: 0,
            observation: "v2. The dashboard shows error rates climbing after the deploy."
        )
        XCTAssertTrue(ReportModelBuilder.shortCaption(for: frame).contains("dashboard"))
    }

    @MainActor
    func testCaptionFallsBackToWindowTitleWithoutAnObservation() {
        let frame = makeFrame(sequence: 0, observation: nil)
        frame.windowTitle = "Q3 Roadmap.key"
        XCTAssertEqual(ReportModelBuilder.shortCaption(for: frame), "Q3 Roadmap.key")
    }

    /// The reported failure: a figure captioned "Zoom call in progress during
    /// early discussion of the design workflow" sat under a screenshot of a
    /// document. That text was the key moment's label — which describes what
    /// was happening in the meeting, not what is in the picture.
    @MainActor
    func testKeyMomentLabelIsNotUsedAsAFigureCaption() {
        let frame = makeFrame(
            sequence: 0,
            observation: "A detailed view of the Disability Decision Tool (DDM template) opened in the design application, showing two AI-suggested RDL entries for Joint Pain."
        )
        let caption = ReportModelBuilder.shortCaption(for: frame)
        XCTAssertTrue(caption.contains("Disability Decision Tool"), "got \(caption)")
        XCTAssertFalse(caption.lowercased().contains("zoom call"))
        XCTAssertFalse(caption.lowercased().contains("discussion"))
    }

    @MainActor
    func testCaptionIsClippedAtAWordBoundary() {
        let frame = makeFrame(sequence: 0, observation: String(repeating: "migration ", count: 60))
        let caption = ReportModelBuilder.shortCaption(for: frame)
        XCTAssertTrue(caption.hasSuffix("…"))
        XCTAssertFalse(caption.dropLast().hasSuffix("migrati"), "clipped mid-word")
    }

    @MainActor
    func testContentScoreRanksSlidesOverVideo() {
        let slide = makeFrame(sequence: 0, observation: "a roadmap slide")
        slide.contentType = .slide
        slide.ocrText = String(repeating: "roadmap ", count: 60)

        let camera = makeFrame(sequence: 1, observation: "participants on camera")
        camera.contentType = .video

        XCTAssertGreaterThan(
            ReportModelBuilder.contentScore(slide),
            ReportModelBuilder.contentScore(camera)
        )
    }

    /// A share that genuinely contains nothing but video must still
    /// illustrate itself — the preference is a score, not a filter.
    @MainActor
    func testAllVideoSessionStillYieldsFrames() {
        let frames = (0..<6).map { index -> ScreenShareFrame in
            let frame = makeFrame(sequence: index, observation: nil)
            frame.contentType = .video
            return frame
        }
        XCTAssertEqual(ReportModelBuilder.representativeFrames(from: frames, limit: 3).count, 3)
    }

    /// A still from a playing video illustrates nothing.
    @MainActor
    func testVisualOnlyFramesAreAvoidedWhenAlternativesExist() {
        var frames = (0..<6).map { makeFrame(sequence: $0, observation: "obs \($0)") }
        frames[1].isVisualOnlyChange = true
        frames[2].isVisualOnlyChange = true

        let picked = ReportModelBuilder.representativeFrames(from: frames, limit: 3)
        XCTAssertFalse(picked.contains { $0.isVisualOnlyChange })
    }

    @MainActor
    func testFewerFramesThanTheLimitReturnsThemAll() {
        let frames = (0..<2).map { makeFrame(sequence: $0, observation: "obs") }
        XCTAssertEqual(ReportModelBuilder.representativeFrames(from: frames, limit: 4).count, 2)
        XCTAssertTrue(ReportModelBuilder.representativeFrames(from: frames, limit: 0).isEmpty)
    }

    @MainActor
    private func makeFrame(sequence: Int, observation: String?) -> ScreenShareFrame {
        let frame = ScreenShareFrame(
            sessionID: UUID(),
            sequence: sequence,
            timestamp: TimeInterval(sequence) * 30,
            imagePath: "frames/test/\(sequence).jpg"
        )
        frame.observation = observation
        return frame
    }

    // MARK: - Emptiness

    func testEmptyReportIsRecognized() {
        XCTAssertTrue(report().isEmpty)
        XCTAssertFalse(report(followUps: ["What about latency?"]).isEmpty)
        XCTAssertFalse(report(transcript: [
            .init(speaker: "Ada", formattedTimestamp: "0:01", text: "Hello")
        ]).isEmpty)
    }

    // MARK: - Filenames

    /// Template codes still have to be unique — they label the picker even
    /// though they are no longer part of the filename.
    func testTemplateCodesAreUniqueAndTwoLetters() {
        let codes = ReportTemplateCatalog.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "duplicate template code in \(codes)")
        for template in ReportTemplateCatalog.all {
            XCTAssertEqual(template.code.count, 2, "\(template.id) code is not two characters")
            XCTAssertEqual(
                template.code, template.code.uppercased(),
                "\(template.id) code should be uppercase so it reads as a tag"
            )
        }
    }

    @MainActor
    func testSuggestedFilenameUsesMeetingIntelligencePattern() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        let meta = ReportModel.Meta(
            title: "North Campus Engineering Scope Review",
            date: date,
            duration: "47:00",
            durationMinutes: 47,
            attendees: [],
            sourceApp: nil,
            generatedAt: .now
        )
        let pdf = ReportExportService.suggestedFilename(for: meta, template: ReportTemplateCatalog.plain)
        XCTAssertEqual(pdf, "North Campus Engineering Scope Review_20260818-47m-intel.pdf")
        let csv = ReportExportService.suggestedFilename(
            for: meta,
            template: ReportTemplateCatalog.plain,
            fileExtension: "csv"
        )
        XCTAssertEqual(csv, "North Campus Engineering Scope Review_20260818-47m-intel.csv")
    }

    @MainActor
    func testSuggestedFilenameStripsPathSeparators() {
        let meta = ReportModel.Meta(
            title: "Q3 / Q4 planning: part 2",
            date: Date(timeIntervalSince1970: 1_777_000_000),
            duration: "1h",
            durationMinutes: 60,
            attendees: [],
            sourceApp: nil,
            generatedAt: .now
        )
        let name = ReportExportService.suggestedFilename(for: meta, template: ReportTemplateCatalog.plain)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
        XCTAssertTrue(name.contains("-intel.pdf"))
    }

    func testDurationMinutesRoundsToNearestMinute() {
        XCTAssertEqual(ReportModelBuilder.durationMinutes(0), 0)
        XCTAssertEqual(ReportModelBuilder.durationMinutes(47 * 60), 47)
        XCTAssertEqual(ReportModelBuilder.durationMinutes(47 * 60 + 20), 47)
        XCTAssertEqual(ReportModelBuilder.durationMinutes(47 * 60 + 40), 48)
    }
}
