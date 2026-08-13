import Foundation

/// The look of a report, and which blocks it shows.
///
/// A template is data: a stylesheet plus a handful of content switches. It
/// never contains markup, because `ReportHTMLRenderer` owns that — which is
/// what keeps a template safe to rewrite (by hand, or later by chat) without
/// any risk of breaking content generation.
struct ReportTemplate: Sendable, Equatable, Identifiable {
    /// Stable across renames — persisted settings and revisions key on it.
    let id: String
    var name: String
    /// Two-letter tag appended to the exported filename, so the same meeting
    /// exported under several templates lands as several files instead of
    /// overwriting itself. Must be unique across the catalog — guarded by
    /// `testTemplateCodesAreUniqueAndTwoLetters`, because a duplicate would
    /// silently reintroduce exactly the clobbering this exists to prevent.
    var code: String
    /// One line shown under the name in the template picker.
    var summary: String
    var css: String

    var includesFigures: Bool = true
    var includesActionItems: Bool = true
    var includesFollowUps: Bool = true
    var includesShareAppendix: Bool = true
    var includesTranscript: Bool = false

    /// Emit a linked table of contents after the header. Whether sections
    /// also start on fresh pages is purely presentational and lives in each
    /// template's stylesheet (`break-before: page`), not here.
    var includesTableOfContents: Bool = false

    /// Print every screenshot in the appendix and have the sections refer
    /// forward to them, instead of setting anchored figures inside the prose.
    /// The formal-report arrangement: evidence at the back, cross-referenced.
    ///
    /// Defaults to false: setting a screenshot beside the point it
    /// illustrates IS the tie to the summary, and it is shorter than the
    /// alternative, which prints the prose, a cross-reference, and the
    /// picture separately. Collecting at the end suits a formal report where
    /// the text should read uninterrupted.
    var figuresAtEnd: Bool = false

    /// Print the screenshots the anchoring pass passed over, in an appendix.
    /// Off by default — this is a summary report, and everything captured is
    /// always available in the app.
    var includesUnpickedFigures: Bool = false

    /// Brand mark, already inlined as a `data:` URI. Templates ship without
    /// one: an approved logo is supplied by the user rather than baked into
    /// the app binary.
    var logoDataURI: String?

    /// The markup vocabulary every template styles against. Kept next to the
    /// type that consumes it so a renderer change and a template change are
    /// visibly the same edit — and so the chat-editing prompt has one
    /// authoritative description to hand the model.
    static let domContract = """
    body.ge-report
      header.ge-header
        img.ge-logo                (optional)
        h1.ge-title
        p.ge-facts > span.ge-fact.ge-fact-date | .ge-fact-duration | .ge-fact-app
        ul.ge-attendees > li.ge-attendee
      section.ge-section
        h2.ge-section-title
        p.ge-section-intro
        ul.ge-points > li.ge-point > span.ge-point-label + span.ge-point-detail
        figure.ge-figure
          img.ge-figure-image
          figcaption.ge-figcaption > span.ge-figure-number + .ge-figure-time + .ge-figure-caption
      section.ge-section.ge-actions
        ul.ge-action-list > li.ge-action.ge-action-open|.ge-action-done
          span.ge-action-text + span.ge-action-assignee
      section.ge-section.ge-followups
        ul.ge-followup-list > li.ge-followup
      section.ge-section.ge-appendix
        div.ge-share-session
          h3.ge-share-title > span.ge-share-range
          p.ge-share-narrative
          ul.ge-moments > li.ge-moment > span.ge-moment-time + span.ge-moment-label
          figure.ge-figure ...
      section.ge-section.ge-transcript
        ul.ge-utterances > li.ge-utterance
          span.ge-speaker + span.ge-utterance-time + span.ge-utterance-text
    """
}

/// Built-in templates. Pure data, following the `ShareAppProfiles` idiom used
/// elsewhere in the app — no seeding, no migration, and "reset to default"
/// is just re-reading this file.
enum ReportTemplateCatalog {

    /// Shared by every template: page geometry, and the invariants a report
    /// must hold whatever it looks like. Templates append their own rules.
    static let base = """
    /* Side margins live on the body, not the page.
       A full-bleed masthead needs to escape the text column, and a negative
       margin cannot leave the @page area — WebKit clips it, so `margin:
       -18mm` produced a header inset exactly one page margin, looking like a
       floating panel (measured 2026-08-12). With the page's side margins at
       zero and the indent applied as body padding, `margin: 0 -18mm` reaches
       the sheet edge. Top and bottom stay on @page so every continuation
       page keeps its margins — body padding would only apply to the first
       and last page of the flow. */
    @page { size: Letter; margin: 18mm 0; }
    * { box-sizing: border-box; }
    /* Printing drops background colours by default, which is sensible for a
       web page and wrong for a designed report: without this the Trajector
       header prints white text on white paper, and every tinted panel
       vanishes. Measured 2026-08-12 — the navy header was invisible. */
    html, body.ge-report, .ge-header, .ge-actions, .ge-toc, .ge-figure-image {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }
    body.ge-report { margin: 0; padding: 0 18mm; }
    /* A figure separated from its caption strands both halves, and the
       caption carries the timestamp that ties it to the recording. */
    .ge-figure { break-inside: avoid; page-break-inside: avoid; }
    .ge-figure-image { display: block; width: 100%; height: auto; }
    /* Never orphan a heading at the foot of a page. */
    .ge-section-title, .ge-share-title { break-after: avoid; page-break-after: avoid; }
    .ge-section { break-inside: auto; }
    /* `ol` as well as `ul`: the contents list is an ordered list numbered by
       a CSS counter, so leaving the native marker on prints both — "1. 1.
       AI-first…". Every list in a report draws its own marker. */
    ul, ol { margin: 0; padding: 0; list-style: none; }
    /* Cross-reference links become real PDF link annotations (verified
       2026-08-12), so a reader can jump from prose to the screenshot that
       evidences it and back. Underlines are omitted deliberately: on paper
       they are noise, and the colour already reads as a reference. */
    a { text-decoration: none; }
    .ge-figure-refs { margin: 6pt 0 0; }
    .ge-figure-ref + .ge-figure-ref { margin-left: 6pt; }
    .ge-figure-back { float: right; }
    .ge-toc-list { counter-reset: ge-toc; }
    .ge-toc-item { break-inside: avoid; }
    """

    /// Opt-in for templates whose header is a full-bleed band: drops the
    /// top margin on page one only, so the band starts at the paper's edge
    /// instead of floating below a white strip. Verified 2026-08-12 —
    /// WebKit's print path honours `@page :first`, and continuation pages
    /// keep their margins.
    ///
    /// Only for templates that actually paint a band. Applied to one whose
    /// header is plain text, it puts the title flush against the paper edge.
    static let flushMasthead = """
    @page :first { margin-top: 0; }
    """

    /// Opt-in rule for one section per page. Not applied by any built-in:
    /// tried on real reports 2026-08-12 and the summary sections are short
    /// enough that it produced pages of white space and a lot of scrolling
    /// between them. Kept because it is the right choice for a long formal
    /// report, and it is one `+ sectionPageBreaks` away.
    static let sectionPageBreaks = """
    .ge-section { break-before: page; page-break-before: always; }
    .ge-appendix, .ge-transcript { break-before: page; page-break-before: always; }
    .ge-share-session { break-before: auto; page-break-before: auto; }
    """

    static let plain = ReportTemplate(
        id: "plain",
        name: "Plain",
        code: "PL",
        summary: "Just the text — no rules, no colour, nothing to distract.",
        css: base + """
        body.ge-report {
            font: 11pt/1.55 -apple-system, "Helvetica Neue", sans-serif;
            color: #111;
        }
        .ge-title { font-size: 19pt; font-weight: 600; margin: 0 0 4pt; }
        .ge-facts { margin: 0 0 2pt; color: #555; font-size: 9.5pt; }
        .ge-fact + .ge-fact::before { content: " · "; }
        .ge-attendees { margin: 0 0 18pt; color: #555; font-size: 9.5pt; }
        .ge-attendee { display: inline; }
        .ge-attendee + .ge-attendee::before { content: ", "; }
        .ge-section { margin: 0 0 16pt; }
        .ge-section-title { font-size: 12.5pt; font-weight: 600; margin: 0 0 6pt; }
        .ge-section-intro { margin: 0 0 6pt; }
        .ge-point { margin: 0 0 5pt; padding-left: 12pt; text-indent: -12pt; }
        .ge-point::before { content: "•  "; color: #666; }
        .ge-point-label { font-weight: 600; }
        .ge-point-label:not(:empty) + .ge-point-detail::before { content: " "; }
        .ge-action { margin: 0 0 4pt; }
        .ge-action-done .ge-action-text { text-decoration: line-through; color: #777; }
        .ge-action-assignee::before { content: " — "; }
        .ge-action-assignee { color: #555; }
        .ge-followup { margin: 0 0 4pt; padding-left: 12pt; text-indent: -12pt; }
        .ge-followup::before { content: "?  "; font-weight: 700; color: #666; }
        .ge-figure { margin: 10pt 0; }
        .ge-figcaption { font-size: 9pt; color: #555; margin-top: 3pt; }
        .ge-figure-number { font-weight: 600; }
        .ge-figure-number::after, .ge-figure-time::after { content: " · "; }
        .ge-share-title { font-size: 11pt; font-weight: 600; margin: 12pt 0 4pt; }
        .ge-share-range { color: #777; font-weight: 400; }
        .ge-share-range::before { content: " "; }
        .ge-moment { font-size: 10pt; margin: 0 0 3pt; }
        .ge-moment-time { color: #777; }
        .ge-moment-time::after { content: "  "; white-space: pre; }
        .ge-utterance { font-size: 9.5pt; margin: 0 0 3pt; }
        .ge-speaker { font-weight: 600; }
        .ge-speaker::after { content: " "; }
        .ge-utterance-time { color: #888; }
        .ge-figure-ref, .ge-figure-back { font-weight: 600; color: #0b5cad; }
        .ge-figure-refs::before { content: "See "; color: #555; font-size: 9pt; }
        .ge-utterance-time::after { content: "  "; white-space: pre; }
        """
    )

    /// Formal reporting register: numbered sections, figure numbering, rules,
    /// serif body. Deliberately monochrome — this is the one you attach to
    /// something official, where colour would read as decoration.
    static let report = ReportTemplate(
        id: "report",
        name: "Report",
        code: "RP",
        summary: "Formal and numbered, with figures collected at the end.",
        css: base + """
        body.ge-report {
            font: 10.5pt/1.6 Charter, Georgia, "Times New Roman", serif;
            color: #1a1a1a;
            counter-reset: ge-section;
        }
        .ge-header { border-bottom: 1.5pt solid #1a1a1a; padding-bottom: 10pt; margin-bottom: 18pt; }
        .ge-title { font-size: 21pt; font-weight: 600; letter-spacing: -0.01em; margin: 0 0 6pt; }
        .ge-facts, .ge-attendees {
            font-family: -apple-system, "Helvetica Neue", sans-serif;
            font-size: 8.5pt; letter-spacing: 0.04em; text-transform: uppercase;
            color: #555; margin: 0;
        }
        .ge-fact + .ge-fact::before { content: " / "; }
        .ge-attendees { margin-top: 4pt; text-transform: none; letter-spacing: 0; font-size: 9pt; }
        .ge-attendee { display: inline; }
        .ge-attendee + .ge-attendee::before { content: ", "; }
        .ge-section { margin: 0 0 18pt; }
        .ge-section-title {
            font-size: 12pt; font-weight: 700; margin: 0 0 8pt;
            padding-bottom: 3pt; border-bottom: 0.5pt solid #bbb;
        }
        .ge-section-title::before {
            counter-increment: ge-section; content: counter(ge-section) ".  ";
            font-variant-numeric: tabular-nums;
        }
        .ge-section-intro { margin: 0 0 8pt; }
        .ge-points { margin: 0; }
        .ge-point { margin: 0 0 6pt; padding-left: 14pt; text-indent: -14pt; }
        .ge-point::before { content: "▪  "; color: #888; }
        .ge-point-label { font-weight: 700; }
        .ge-point-label:not(:empty)::after { content: " — "; font-weight: 400; color: #666; }
        .ge-actions .ge-action { margin: 0 0 5pt; padding-left: 14pt; text-indent: -14pt; }
        .ge-action-open::before { content: "☐  "; }
        .ge-action-done::before { content: "☑  "; }
        .ge-action-done .ge-action-text { color: #777; }
        .ge-action-assignee {
            font-family: -apple-system, sans-serif; font-size: 8.5pt;
            text-transform: uppercase; letter-spacing: 0.04em; color: #666;
        }
        .ge-action-assignee::before { content: "  ·  "; }
        .ge-followup { margin: 0 0 5pt; padding-left: 14pt; text-indent: -14pt; }
        .ge-followup::before { content: "→  "; color: #888; }
        .ge-figure { margin: 12pt 0; }
        .ge-figure-image { border: 0.5pt solid #ccc; }
        .ge-figcaption {
            font-family: -apple-system, sans-serif; font-size: 8.5pt;
            color: #555; margin-top: 4pt; padding-top: 3pt; border-top: 0.5pt solid #ddd;
        }
        .ge-figure-number { font-weight: 700; color: #1a1a1a; }
        .ge-figure-number::after { content: ".  "; }
        .ge-figure-time { font-variant-numeric: tabular-nums; }
        .ge-figure-time::after { content: "  ·  "; }
        .ge-share-title { font-size: 10.5pt; font-weight: 700; margin: 12pt 0 4pt; }
        .ge-share-range {
            font-family: -apple-system, sans-serif; font-weight: 400;
            font-size: 8.5pt; color: #777;
        }
        .ge-share-range::before { content: "   "; white-space: pre; }
        .ge-share-narrative { margin: 0 0 6pt; }
        .ge-moment { margin: 0 0 3pt; padding-left: 40pt; text-indent: -40pt; font-size: 10pt; }
        .ge-moment-time {
            display: inline-block; width: 36pt; color: #777;
            font-variant-numeric: tabular-nums;
        }
        .ge-utterance { font-size: 9pt; margin: 0 0 3pt; }
        .ge-speaker { font-weight: 700; }
        .ge-speaker::after { content: "  "; white-space: pre; }
        .ge-utterance-time { color: #999; font-variant-numeric: tabular-nums; }
        .ge-utterance-time::after { content: "  "; white-space: pre; }
        .ge-figure-ref, .ge-figure-back {
            font-family: -apple-system, sans-serif; font-size: 8.5pt;
            font-weight: 700; color: #1a1a1a;
        }
        .ge-figure-refs::before {
            content: "See "; font-family: -apple-system, sans-serif;
            font-size: 8.5pt; color: #666;
        }
        """,
        includesTableOfContents: true
    )

    /// Trajector. Palette lifted from the live theme stylesheet
    /// (`themes/trajector/dist/css/trajector.min.css`, read 2026-08-12):
    /// navy #00073e, blue #184997, crimson #b52d38, surface #f1f4f9. The site
    /// sets Montserrat; Avenir Next is the closest geometric sans already on
    /// every Mac, and stands in until the real face is bundled.
    static let trajector = ReportTemplate(
        id: "trajector",
        name: "Trajector",
        code: "TJ",
        summary: "Corporate navy and blue, in the company's own palette.",
        css: base + """
        body.ge-report {
            font: 10.5pt/1.6 Montserrat, "Avenir Next", "Helvetica Neue", sans-serif;
            color: #22262e;
        }
        .ge-header {
            background: #00073e; color: #fff;
            margin: 0 -18mm 16pt; padding: 14mm 18mm 12mm;
        }
        .ge-logo { max-height: 30pt; width: auto; margin-bottom: 10pt; display: block; }
        .ge-title { font-size: 22pt; font-weight: 700; letter-spacing: -0.02em; margin: 0 0 6pt; }
        .ge-facts { margin: 0; font-size: 9pt; color: #b9c9e0; }
        .ge-fact + .ge-fact::before { content: "  ·  "; }
        .ge-attendees { margin: 5pt 0 0; font-size: 9pt; color: #b9c9e0; }
        .ge-attendee { display: inline; }
        .ge-attendee + .ge-attendee::before { content: ", "; }
        .ge-section { margin: 0 0 16pt; }
        .ge-section-title {
            font-size: 12pt; font-weight: 700; color: #00073e; margin: 0 0 7pt;
            padding-left: 8pt; border-left: 3pt solid #184997;
        }
        .ge-section-intro { margin: 0 0 7pt; }
        .ge-point { margin: 0 0 6pt; padding-left: 13pt; text-indent: -13pt; }
        .ge-point::before { content: "●  "; color: #184997; font-size: 7pt; }
        .ge-point-label { font-weight: 700; color: #0e2955; }
        .ge-point-label:not(:empty)::after { content: " — "; font-weight: 400; color: #6b7280; }
        .ge-actions { background: #f1f4f9; padding: 10pt 12pt; border-radius: 3pt; }
        .ge-actions .ge-section-title { border-left: none; padding-left: 0; }
        .ge-action { margin: 0 0 5pt; padding-left: 13pt; text-indent: -13pt; }
        .ge-action-open::before { content: "▸  "; color: #b52d38; font-weight: 700; }
        .ge-action-done::before { content: "✓  "; color: #6b7280; }
        .ge-action-done .ge-action-text { color: #6b7280; text-decoration: line-through; }
        .ge-action-assignee { color: #184997; font-weight: 600; font-size: 9.5pt; }
        .ge-action-assignee::before { content: "  ·  "; color: #9aa5b1; font-weight: 400; }
        .ge-followup { margin: 0 0 5pt; padding-left: 13pt; text-indent: -13pt; }
        .ge-followup::before { content: "?  "; color: #b52d38; font-weight: 700; }
        .ge-figure { margin: 12pt 0; }
        .ge-figure-image { border: 1pt solid #b9c9e0; border-radius: 2pt; }
        .ge-figcaption { font-size: 8.5pt; color: #52606d; margin-top: 4pt; }
        .ge-figure-number {
            background: #184997; color: #fff; font-weight: 700;
            padding: 1pt 5pt; border-radius: 2pt; font-size: 8pt;
        }
        .ge-figure-number::after { content: ""; }
        .ge-figure-time { color: #9aa5b1; font-variant-numeric: tabular-nums; }
        .ge-figure-time::before { content: "  "; white-space: pre; }
        .ge-figure-time::after { content: "  ·  "; }
        .ge-share-title { font-size: 10.5pt; font-weight: 700; color: #00073e; margin: 12pt 0 4pt; }
        .ge-share-range { font-weight: 400; font-size: 8.5pt; color: #9aa5b1; }
        .ge-share-range::before { content: "   "; white-space: pre; }
        .ge-share-narrative { margin: 0 0 6pt; }
        .ge-moment { margin: 0 0 3pt; padding-left: 40pt; text-indent: -40pt; font-size: 10pt; }
        .ge-moment-time {
            display: inline-block; width: 36pt; color: #184997;
            font-weight: 600; font-variant-numeric: tabular-nums;
        }
        .ge-utterance { font-size: 9pt; margin: 0 0 3pt; }
        .ge-speaker { font-weight: 700; color: #0e2955; }
        .ge-speaker::after { content: "  "; white-space: pre; }
        .ge-utterance-time { color: #9aa5b1; font-variant-numeric: tabular-nums; }
        .ge-figure-ref, .ge-figure-back { font-weight: 700; color: #184997; font-size: 9pt; }
        .ge-figure-refs::before { content: "See "; color: #7b8794; font-size: 9pt; font-weight: 400; }
        .ge-utterance-time::after { content: "  "; white-space: pre; }
        .ge-toc { background: #f1f4f9; padding: 12pt 14pt; margin: 0 0 18pt; }
        .ge-toc-title {
            font-size: 9pt; font-weight: 700; letter-spacing: 0.08em;
            text-transform: uppercase; color: #184997; margin: 0 0 8pt;
        }
        .ge-toc-item { margin: 0 0 4pt; }
        .ge-toc-link { color: #00073e; font-weight: 600; }
        .ge-toc-item::before {
            counter-increment: ge-toc; content: counter(ge-toc) ".  ";
            color: #184997; font-weight: 700; font-variant-numeric: tabular-nums;
        }
        """ + flushMasthead,
        includesTableOfContents: true
    )

    /// Matthew Purdon. The site is dark-first (charcoal #242220 ground, cream
    /// #FFF6E6 text); printing that would flood the page with ink, so this is
    /// the honest print inversion of the same identity — cream paper, ink
    /// text, amber rules, the Canada red accent kept for emphasis. The site's
    /// mono-label / serif-prose pairing is preserved with the nearest faces
    /// macOS ships, standing in for IBM Plex until it is bundled.
    static let matthewPurdon = ReportTemplate(
        id: "purdon",
        name: "Matthew Purdon",
        code: "MP",
        summary: "Editorial: cream paper, serif prose, amber rules, mono labels.",
        css: base + """
        /* Cream as a full-bleed masthead rather than the whole sheet. Three
           ways to paint the page cream were tried on 2026-08-12 and none
           works in WebKit's print path: a background on `body` paints only
           the content box, one on `html` does not propagate to the page
           canvas, and a fixed-position bleed layer is clipped to the page
           area. Negative margins on a normal-flow block DO escape the @page
           margin, so the band is real and the paper stays white. */
        body.ge-report {
            font: 11pt/1.7 Charter, Georgia, "Iowan Old Style", serif;
            color: #272325;
        }
        .ge-header {
            background: #FFF6E6;
            margin: 0 -18mm 20pt;
            padding: 12mm 18mm 10mm;
            border-bottom: 2pt solid #b7781f;
        }
        .ge-logo { max-height: 26pt; width: auto; margin-bottom: 10pt; display: block; }
        .ge-title {
            font-size: 23pt; font-weight: 600; line-height: 1.15;
            letter-spacing: -0.02em; margin: 0 0 8pt; color: #272325;
        }
        .ge-facts, .ge-attendees {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 8pt; letter-spacing: 0.08em; text-transform: uppercase;
            color: #a47738; margin: 0;
        }
        .ge-fact + .ge-fact::before { content: "  ·  "; }
        .ge-attendees {
            margin-top: 8pt; padding-top: 8pt; border-top: 1pt solid rgba(39,35,37,0.14);
            text-transform: none; letter-spacing: 0.02em; color: #6b625a;
        }
        .ge-attendee { display: inline; }
        .ge-attendee + .ge-attendee::before { content: ", "; }
        .ge-section { margin: 0 0 20pt; }
        .ge-section-title {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 9.5pt; font-weight: 700; letter-spacing: 0.08em;
            text-transform: uppercase; color: #b7781f; margin: 0 0 8pt;
        }
        .ge-section-intro { margin: 0 0 8pt; }
        .ge-point { margin: 0 0 7pt; padding-left: 15pt; text-indent: -15pt; }
        .ge-point::before { content: "◆  "; color: #b7781f; font-size: 8pt; }
        .ge-point-label { font-weight: 600; }
        .ge-point-label:not(:empty)::after { content: ". "; font-weight: 400; }
        .ge-actions {
            border-left: 2pt solid #b7781f; padding-left: 12pt;
        }
        .ge-action { margin: 0 0 6pt; padding-left: 15pt; text-indent: -15pt; }
        .ge-action-open::before { content: "▢  "; color: #b7781f; }
        .ge-action-done::before { content: "▣  "; color: #8b8b80; }
        .ge-action-done .ge-action-text { color: #8b8b80; }
        .ge-action-assignee {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 8pt; letter-spacing: 0.04em; color: #d52b1e;
        }
        .ge-action-assignee::before { content: "  ·  "; color: #a89e94; }
        .ge-followup { margin: 0 0 6pt; padding-left: 15pt; text-indent: -15pt; font-style: italic; }
        .ge-followup::before { content: "?  "; color: #d52b1e; font-style: normal; font-weight: 700; }
        .ge-figure { margin: 14pt 0; }
        .ge-figure-image { border: 1pt solid rgba(39,35,37,0.16); }
        .ge-figcaption {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 7.5pt; letter-spacing: 0.03em; color: #6b625a; margin-top: 5pt;
        }
        .ge-figure-number { color: #b7781f; font-weight: 700; }
        .ge-figure-number::after { content: "  ·  "; color: #a89e94; font-weight: 400; }
        .ge-figure-time::after { content: "  ·  "; color: #a89e94; }
        .ge-share-title {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 9pt; font-weight: 700; letter-spacing: 0.04em;
            color: #272325; margin: 14pt 0 5pt;
        }
        .ge-share-range { font-weight: 400; color: #a89e94; }
        .ge-share-range::before { content: "   "; white-space: pre; }
        .ge-share-narrative { margin: 0 0 7pt; }
        .ge-moment { margin: 0 0 4pt; padding-left: 40pt; text-indent: -40pt; font-size: 10pt; }
        .ge-moment-time {
            display: inline-block; width: 36pt;
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 8pt; color: #b7781f;
        }
        .ge-utterance { font-size: 9.5pt; margin: 0 0 4pt; }
        .ge-speaker { font-weight: 600; }
        .ge-speaker::after { content: "  "; white-space: pre; }
        .ge-utterance-time {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 8pt; color: #a89e94;
        }
        .ge-figure-ref, .ge-figure-back {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 7.5pt; letter-spacing: 0.04em; color: #d52b1e;
        }
        .ge-figure-refs::before {
            content: "See "; font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 7.5pt; color: #a89e94;
        }
        .ge-utterance-time::after { content: "  "; white-space: pre; }
        .ge-toc { margin: 0 0 20pt; padding-bottom: 12pt; border-bottom: 1pt solid rgba(39,35,37,0.14); }
        .ge-toc-title {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 9.5pt; font-weight: 700; letter-spacing: 0.08em;
            text-transform: uppercase; color: #b7781f; margin: 0 0 8pt;
        }
        .ge-toc-item { margin: 0 0 5pt; }
        .ge-toc-link { color: #272325; }
        .ge-toc-item::before {
            counter-increment: ge-toc; content: counter(ge-toc) ".  ";
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 8pt; color: #b7781f;
        }
        """ + flushMasthead,
        includesTableOfContents: true
    )

    /// PurdonMoi. No existing brand to draw on, so: neutral corporate done
    /// properly — graphite and slate, generous whitespace, hairline rules, and
    /// exactly one accent used sparingly enough that it still means something.
    static let purdonMoi = ReportTemplate(
        id: "purdonmoi",
        name: "PurdonMoi",
        code: "MO",
        summary: "Clean corporate: graphite and slate with a single teal accent.",
        css: base + """
        body.ge-report {
            font: 10.5pt/1.65 "Helvetica Neue", -apple-system, Arial, sans-serif;
            color: #1f2933;
        }
        .ge-header { margin-bottom: 22pt; }
        .ge-logo { max-height: 28pt; width: auto; margin-bottom: 12pt; display: block; }
        .ge-title {
            font-size: 24pt; font-weight: 300; letter-spacing: -0.02em;
            margin: 0 0 10pt; color: #1f2933;
        }
        .ge-facts {
            margin: 0; font-size: 8.5pt; letter-spacing: 0.1em;
            text-transform: uppercase; color: #7b8794;
        }
        .ge-fact + .ge-fact::before { content: "  |  "; color: #cbd2d9; }
        .ge-attendees {
            margin: 10pt 0 0; padding-top: 10pt;
            border-top: 0.5pt solid #e4e7eb; font-size: 9pt; color: #52606d;
        }
        .ge-attendee { display: inline; }
        .ge-attendee + .ge-attendee::before { content: "  ·  "; color: #cbd2d9; }
        .ge-section { margin: 0 0 20pt; }
        .ge-section-title {
            font-size: 11pt; font-weight: 600; letter-spacing: 0.02em;
            color: #1f2933; margin: 0 0 9pt;
        }
        .ge-section-title::after {
            content: ""; display: block; width: 24pt; height: 2pt;
            background: #0b7285; margin-top: 5pt;
        }
        .ge-section-intro { margin: 0 0 8pt; color: #3e4c59; }
        .ge-point { margin: 0 0 6pt; padding-left: 13pt; text-indent: -13pt; }
        .ge-point::before { content: "•  "; color: #0b7285; }
        .ge-point-label { font-weight: 600; }
        .ge-point-label:not(:empty)::after { content: " — "; font-weight: 400; color: #7b8794; }
        .ge-actions { background: #f5f7fa; padding: 12pt 14pt; }
        .ge-actions .ge-section-title::after { background: #0b7285; }
        .ge-action { margin: 0 0 6pt; padding-left: 13pt; text-indent: -13pt; }
        .ge-action-open::before { content: "○  "; color: #0b7285; }
        .ge-action-done::before { content: "●  "; color: #9aa5b1; }
        .ge-action-done .ge-action-text { color: #7b8794; text-decoration: line-through; }
        .ge-action-assignee {
            font-size: 8.5pt; letter-spacing: 0.06em; text-transform: uppercase; color: #0b7285;
        }
        .ge-action-assignee::before { content: "  ·  "; color: #cbd2d9; letter-spacing: 0; }
        .ge-followup { margin: 0 0 6pt; padding-left: 13pt; text-indent: -13pt; color: #3e4c59; }
        .ge-followup::before { content: "→  "; color: #0b7285; }
        .ge-figure { margin: 14pt 0; }
        .ge-figure-image { border: 0.5pt solid #e4e7eb; }
        .ge-figcaption {
            font-size: 8pt; color: #7b8794; margin-top: 5pt;
            padding-left: 8pt; border-left: 2pt solid #0b7285;
        }
        .ge-figure-number { font-weight: 600; color: #1f2933; letter-spacing: 0.04em; }
        .ge-figure-number::after { content: "  ·  "; color: #cbd2d9; font-weight: 400; }
        .ge-figure-time { font-variant-numeric: tabular-nums; }
        .ge-figure-time::after { content: "  ·  "; color: #cbd2d9; }
        .ge-share-title { font-size: 10pt; font-weight: 600; color: #1f2933; margin: 14pt 0 5pt; }
        .ge-share-range { font-weight: 400; font-size: 8.5pt; color: #9aa5b1; }
        .ge-share-range::before { content: "   "; white-space: pre; }
        .ge-share-narrative { margin: 0 0 7pt; color: #3e4c59; }
        .ge-moment { margin: 0 0 4pt; padding-left: 40pt; text-indent: -40pt; font-size: 9.5pt; }
        .ge-moment-time {
            display: inline-block; width: 36pt; color: #0b7285;
            font-weight: 600; font-variant-numeric: tabular-nums;
        }
        .ge-utterance { font-size: 9pt; margin: 0 0 3pt; }
        .ge-speaker { font-weight: 600; }
        .ge-speaker::after { content: "  "; white-space: pre; }
        .ge-utterance-time { color: #9aa5b1; font-variant-numeric: tabular-nums; }
        .ge-figure-ref, .ge-figure-back {
            font-weight: 600; color: #0b7285; font-size: 9pt; letter-spacing: 0.02em;
        }
        .ge-figure-refs::before { content: "See "; color: #7b8794; font-weight: 400; font-size: 9pt; }
        .ge-utterance-time::after { content: "  "; white-space: pre; }
        .ge-toc { margin: 0 0 22pt; }
        .ge-toc-title {
            font-size: 8.5pt; font-weight: 600; letter-spacing: 0.1em;
            text-transform: uppercase; color: #7b8794; margin: 0 0 8pt;
        }
        .ge-toc-item { margin: 0 0 5pt; }
        .ge-toc-link { color: #1f2933; font-weight: 500; }
        .ge-toc-item::before {
            counter-increment: ge-toc; content: counter(ge-toc) "  ";
            color: #0b7285; font-weight: 600; font-variant-numeric: tabular-nums;
        }
        """,
        includesTableOfContents: true
    )

    static let all: [ReportTemplate] = [plain, report, trajector, matthewPurdon, purdonMoi]

    static func template(id: String) -> ReportTemplate {
        all.first { $0.id == id } ?? plain
    }
}
