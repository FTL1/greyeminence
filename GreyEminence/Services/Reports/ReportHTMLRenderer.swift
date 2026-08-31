import Foundation

/// Turns a `ReportModel` into a single self-contained HTML document.
///
/// The split of responsibility matters: this renderer owns the *markup*, a
/// `ReportTemplate` owns the *stylesheet*. The markup uses a fixed vocabulary
/// of `ge-` class names, documented in `ReportTemplate.domContract`, and that
/// stability is what will later make it safe to let the model rewrite a
/// template's CSS by chat — it can restyle anything and break nothing.
///
/// The output never references an external host. Images are inlined as
/// `data:` URIs and fonts are embedded the same way, so the document renders
/// identically in the PDF renderer, in a preview, and in any future upload —
/// and a report can never phone home to fetch a logo.
enum ReportHTMLRenderer {

    static func render(_ report: ReportModel, template: ReportTemplate) -> String {
        // Figures are numbered once, up front, in reading order — the number
        // is part of a figure's identity because sections refer to it by name
        // ("see Figure 3") and link to it by id.
        var numbers: [UUID: Int] = [:]
        for (offset, figure) in report.allFigures.enumerated() {
            numbers[figure.id] = offset + 1
        }
        func number(_ figure: ReportModel.Figure) -> Int { numbers[figure.id] ?? 0 }

        // Which appendix figures each section should point forward to.
        var referencesBySection: [Int: [ReportModel.Figure]] = [:]
        for figure in report.shareSessions.flatMap(\.figures) {
            guard let index = figure.sectionIndex else { continue }
            referencesBySection[index, default: []].append(figure)
        }

        var body: [String] = []
        body.append(header(report, template: template))

        if template.includesTableOfContents {
            body.append(tableOfContentsHTML(report, template: template))
        }

        // Ahead of the summary, and styled as a callout rather than a
        // section: what is still unresolved is what a reader most needs, and
        // given the same heading treatment as the summary it read as one more
        // of its sections.
        if template.includesFollowUps, !report.followUpQuestions.isEmpty {
            body.append(followUpsHTML(report.followUpQuestions))
        }

        for section in report.sections {
            body.append(sectionHTML(
                section,
                template: template,
                number: number,
                references: template.includesFigures ? (referencesBySection[section.id] ?? []) : []
            ))
        }

        if template.includesActionItems, !report.actionItems.isEmpty {
            body.append(actionItemsHTML(report.actionItems))
        }

        if !report.topics.isEmpty {
            body.append(topicsHTML(report.topics))
        }

        if template.includesShareAppendix {
            let sessions = report.shareSessions.filter {
                !$0.narrative.isEmpty || !$0.figures.isEmpty
            }
            if !sessions.isEmpty {
                body.append(appendixHTML(sessions, template: template, number: number))
            }
        }

        if template.includesTranscript, !report.transcript.isEmpty {
            body.append(transcriptHTML(report.transcript))
        }

        return document(body: body.joined(separator: "\n"), template: template)
    }

    // MARK: - Document shell

    private static func document(body: String, template: ReportTemplate) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <style>
        \(template.css)
        </style>
        </head>
        <body class="ge-report">
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Blocks

    private static func header(_ report: ReportModel, template: ReportTemplate) -> String {
        let meta = report.meta
        var lines: [String] = ["<header class=\"ge-header\">"]

        if let logo = template.logoDataURI {
            lines.append("<img class=\"ge-logo\" src=\"\(logo)\" alt=\"\">")
        }
        lines.append("<h1 class=\"ge-title\">\(escape(meta.title))</h1>")

        var facts: [String] = [
            "<span class=\"ge-fact ge-fact-date\">\(escape(longDate(meta.date)))</span>",
            "<span class=\"ge-fact ge-fact-duration\">\(escape(meta.duration))</span>",
        ]
        if let app = meta.sourceApp {
            facts.append("<span class=\"ge-fact ge-fact-app\">\(escape(app))</span>")
        }
        lines.append("<p class=\"ge-facts\">\(facts.joined(separator: ""))</p>")

        if !meta.attendees.isEmpty {
            let names = meta.attendees.map { "<li class=\"ge-attendee\">\(escape($0))</li>" }
            lines.append("<ul class=\"ge-attendees\">\(names.joined())</ul>")
        }
        lines.append("</header>")
        return lines.joined(separator: "\n")
    }

    /// Linked contents. Entries become real PDF link annotations, so this is
    /// working navigation in the exported document, not decoration.
    ///
    /// No page numbers: WebKit's paged-media support has no `counter(page)`
    /// outside `@page`, and no `target-counter()`, so a printed number would
    /// have to be discovered by rendering once and re-rendering — and there
    /// are no page numbers printed on the pages for it to refer to anyway.
    /// Clickable entries are the navigation that actually works here.
    private static func tableOfContentsHTML(
        _ report: ReportModel,
        template: ReportTemplate
    ) -> String {
        var entries: [(anchor: String, title: String)] = report.sections.map {
            (sectionAnchor($0.id), $0.title)
        }
        if template.includesFollowUps, !report.followUpQuestions.isEmpty {
            entries.insert(("ge-followups", "Open questions"), at: 0)
        }
        if template.includesActionItems, !report.actionItems.isEmpty {
            entries.append(("ge-actions", "Action items"))
        }
        if !report.topics.isEmpty {
            entries.append(("ge-topics", "Topics"))
        }
        if template.includesShareAppendix,
           report.shareSessions.contains(where: { !$0.narrative.isEmpty || !$0.figures.isEmpty }) {
            entries.append(("ge-appendix", "Shared screens"))
        }
        if template.includesTranscript, !report.transcript.isEmpty {
            entries.append(("ge-transcript", "Transcript"))
        }

        // One entry is not a table of contents, it is a redundant heading.
        guard entries.count > 1 else { return "" }

        let items = entries.map { entry in
            """
            <li class="ge-toc-item">\
            <a class="ge-toc-link" href="#\(entry.anchor)">\(escape(entry.title))</a></li>
            """
        }
        return """
        <nav class="ge-toc">
        <h2 class="ge-toc-title">Contents</h2>
        <ol class="ge-toc-list">\(items.joined())</ol>
        </nav>
        """
    }

    private static func sectionHTML(
        _ section: ReportModel.Section,
        template: ReportTemplate,
        number: (ReportModel.Figure) -> Int,
        references: [ReportModel.Figure]
    ) -> String {
        var lines: [String] = ["<section class=\"ge-section\" id=\"\(sectionAnchor(section.id))\">"]
        lines.append("<h2 class=\"ge-section-title\">\(escape(section.title))</h2>")

        if let intro = section.intro, !intro.isEmpty {
            lines.append("<p class=\"ge-section-intro\">\(escape(intro))</p>")
        }

        if !section.points.isEmpty {
            lines.append("<ul class=\"ge-points\">")
            for point in section.points {
                lines.append("""
                <li class="ge-point">\
                <span class="ge-point-label">\(escape(point.label))</span>\
                <span class="ge-point-detail">\(escape(point.detail))</span>\
                </li>
                """)
            }
            lines.append("</ul>")
        }

        if template.includesFigures {
            for figure in section.figures {
                lines.append(figureHTML(figure, number: number(figure), showsBackLink: false))
            }
        }

        // Evidence that prints at the back still belongs to this section, so
        // point the reader at it. These become real PDF link annotations.
        if !references.isEmpty {
            let links = references
                .sorted { number($0) < number($1) }
                .map { figure in
                    """
                    <a class="ge-figure-ref" href="#\(figureAnchor(figure))">\
                    Figure \(number(figure))</a>
                    """
                }
            lines.append("<p class=\"ge-figure-refs\">\(links.joined(separator: ""))</p>")
        }

        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    /// Fragment identifiers. Kept in one place because the anchor and the
    /// link that targets it must agree exactly — a mismatch produces a dead
    /// link in the PDF with no other symptom.
    static func sectionAnchor(_ index: Int) -> String { "ge-section-\(index)" }
    static func figureAnchor(_ figure: ReportModel.Figure) -> String {
        "ge-figure-\(figure.id.uuidString.lowercased())"
    }

    /// Figures are `break-inside: avoid` in every stylesheet — the caption
    /// carries the timestamp that ties the image back to the recording, so a
    /// page break between them would strand both halves.
    private static func figureHTML(
        _ figure: ReportModel.Figure,
        number: Int,
        showsBackLink: Bool
    ) -> String {
        let source = "data:image/jpeg;base64,\(figure.imageData.base64EncodedString())"
        // A screenshot printed away from the prose it evidences is stranded
        // without this — it is the return half of the section's forward link.
        var backLink = ""
        if showsBackLink, let index = figure.sectionIndex, let title = figure.sectionTitle {
            backLink = """
            <a class="ge-figure-back" href="#\(sectionAnchor(index))">↩ \(escape(title))</a>
            """
        }
        return """
        <figure class="ge-figure" id="\(figureAnchor(figure))">
        <img class="ge-figure-image" src="\(source)" alt="\(escape(figure.caption))">
        <figcaption class="ge-figcaption">\
        <span class="ge-figure-number">Figure \(number)</span>\
        <span class="ge-figure-time">\(escape(figure.formattedTimestamp))</span>\
        <span class="ge-figure-caption">\(escape(figure.caption))</span>\(backLink)\
        </figcaption>
        </figure>
        """
    }

    private static func actionItemsHTML(_ items: [ReportModel.ActionItem]) -> String {
        var lines: [String] = [
            "<section class=\"ge-section ge-actions\" id=\"ge-actions\">",
            "<h2 class=\"ge-section-title\">Action items</h2>",
            "<ul class=\"ge-action-list\">",
        ]
        for item in items {
            let state = item.isCompleted ? "ge-action-done" : "ge-action-open"
            let assignee = item.assignee.map {
                "<span class=\"ge-action-assignee\">\(escape($0))</span>"
            } ?? ""
            lines.append("""
            <li class="ge-action \(state)">\
            <span class="ge-action-text">\(escape(item.text))</span>\(assignee)</li>
            """)
        }
        lines.append("</ul>")
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    private static func followUpsHTML(_ questions: [String]) -> String {
        let items = questions.map { "<li class=\"ge-followup\">\(escape($0))</li>" }
        return """
        <section class="ge-callout ge-followups" id="ge-followups">
        <h2 class="ge-callout-title">Open questions</h2>
        <ul class="ge-followup-list">\(items.joined())</ul>
        </section>
        """
    }

    private static func topicsHTML(_ topics: [String]) -> String {
        let items = topics.map { "<li class=\"ge-topic\">\(escape($0))</li>" }
        return """
        <section class="ge-section ge-topics" id="ge-topics">
        <h2 class="ge-section-title">Topics</h2>
        <ul class="ge-topic-list">\(items.joined())</ul>
        </section>
        """
    }

    private static func appendixHTML(
        _ sessions: [ReportModel.ShareSession],
        template: ReportTemplate,
        number: (ReportModel.Figure) -> Int
    ) -> String {
        var lines: [String] = [
            "<section class=\"ge-section ge-appendix\" id=\"ge-appendix\">",
            "<h2 class=\"ge-section-title\">Shared screens</h2>",
        ]
        for session in sessions {
            lines.append("<div class=\"ge-share-session\">")
            let title = session.windowTitle.map { escape($0) } ?? "Shared screen"
            lines.append("""
            <h3 class="ge-share-title">\(title)\
            <span class="ge-share-range">\(escape(session.startLabel))–\(escape(session.endLabel))</span></h3>
            """)
            if !session.narrative.isEmpty {
                lines.append("<p class=\"ge-share-narrative\">\(escape(session.narrative))</p>")
            }
            if !session.keyMoments.isEmpty {
                let moments = session.keyMoments.map {
                    """
                    <li class="ge-moment">\
                    <span class="ge-moment-time">\(escape($0.formattedTimestamp))</span>\
                    <span class="ge-moment-label">\(escape($0.label))</span></li>
                    """
                }
                lines.append("<ul class=\"ge-moments\">\(moments.joined())</ul>")
            }
            if template.includesFigures {
                for figure in session.figures {
                    lines.append(figureHTML(figure, number: number(figure), showsBackLink: true))
                }
            }
            lines.append("</div>")
        }
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    private static func transcriptHTML(_ lines: [ReportModel.TranscriptLine]) -> String {
        let rows = lines.map {
            """
            <li class="ge-utterance">\
            <span class="ge-speaker">\(escape($0.speaker))</span>\
            <span class="ge-utterance-time">\(escape($0.formattedTimestamp))</span>\
            <span class="ge-utterance-text">\(escape($0.text))</span></li>
            """
        }
        return """
        <section class="ge-section ge-transcript" id="ge-transcript">
        <h2 class="ge-section-title">Transcript</h2>
        <ul class="ge-utterances">\(rows.joined())</ul>
        </section>
        """
    }

    // MARK: - Helpers

    /// Meeting titles, transcripts and OCR text are arbitrary user content —
    /// a stray `<` must never become markup, and `&` must not swallow the
    /// text after it. Ampersand goes first or it would re-escape the others.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func longDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }
}
