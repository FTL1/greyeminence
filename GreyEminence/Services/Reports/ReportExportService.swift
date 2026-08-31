import AppKit
import Foundation

/// Ties the report pipeline together: snapshot a meeting, render it, ask the
/// user where to put the PDF, write it.
@MainActor
enum ReportExportService {

    /// How many screenshots a report may carry when there is no anchoring
    /// plan to choose them. Small on purpose: unplaced pictures are the ones
    /// that make a summary long without making it clearer.
    static let unplannedFigureLimit = 3

    enum ExportError: LocalizedError {
        case nothingToReport

        var errorDescription: String? {
            switch self {
            case .nothingToReport:
                "This meeting has nothing selected to export yet."
            }
        }
    }

    /// Build and save a PDF for `meeting`. Returns the chosen URL, or nil if
    /// the user cancelled the save panel.
    @discardableResult
    /// `figuresAtEnd` overrides the template's own preference when the user
    /// has expressed one; nil keeps whatever the template asks for.
    static func exportPDF(
        for meeting: Meeting,
        template: ReportTemplate = ReportTemplateCatalog.plain,
        figuresAtEnd: Bool? = nil
    ) async throws -> URL? {
        try await export(
            for: meeting,
            selection: IntelligenceExportSelection(
                includeSummary: true,
                includeActionItems: true,
                includeQuestions: true,
                includeTopics: true,
                includeSharedScreens: true,
                includeTranscript: template.includesTranscript,
                dedupeTranscript: true
            ),
            format: .pdf,
            template: template,
            figuresAtEnd: figuresAtEnd
        )
    }

    @discardableResult
    static func export(
        for meeting: Meeting,
        selection: IntelligenceExportSelection,
        format: IntelligenceExportFormat,
        template: ReportTemplate = ReportTemplateCatalog.plain,
        figuresAtEnd: Bool? = nil
    ) async throws -> URL? {
        var report = ReportModelBuilder.build(
            from: meeting,
            includeTranscript: selection.includeTranscript,
            dedupeTranscript: selection.dedupeTranscript
        )
        guard selection.includesAnything else { throw ExportError.nothingToReport }

        // Ask before rendering: a cancelled save should not have cost the
        // user a few seconds of layout and a pile of base64.
        guard let destination = savePanelURL(
            for: report.meta,
            format: format
        ) else { return nil }

        if format == .pdf, template.includesFigures, selection.includeSharedScreens || selection.includeSummary {
            if let plan = await anchorPlan(for: meeting, report: report) {
                report = report.applyingAnchors(
                    plan,
                    figuresAtEnd: figuresAtEnd ?? template.figuresAtEnd,
                    keepsUnpicked: template.includesUnpickedFigures
                )
            } else {
                // No plan — AI unconfigured, offline, or unparseable. Without
                // one, nothing can be tied to a section, so fall back to a
                // handful of the most content-bearing screenshots rather than
                // every one the builder gathered.
                report = report.keepingBestFigures(limit: Self.unplannedFigureLimit)
            }
        }

        // Last, so the anchoring above still sees the full section list its
        // cached plan was computed against.
        report = selection.applying(to: report)
        guard !report.isEmpty else { throw ExportError.nothingToReport }

        try await write(report, format: format, template: template, selection: selection, to: destination)

        LogManager.send(
            "Exported report: \"\(report.meta.title)\" (\(format.fileExtension), \(report.sections.count) sections, \(report.allFigures.count) figures)",
            category: .general,
            meetingID: meeting.id
        )
        // A report with no pictures is the most confusing possible outcome, so
        // say which of the several reasons it was.
        if format == .pdf, template.includesFigures, report.allFigures.isEmpty {
            LogManager.send(
                "Report has no figures: \(figureDiagnosis(for: meeting))",
                category: .general,
                level: .warning,
                meetingID: meeting.id
            )
        }
        return destination
    }

    private static func write(
        _ report: ReportModel,
        format: IntelligenceExportFormat,
        template: ReportTemplate,
        selection: IntelligenceExportSelection,
        to url: URL
    ) async throws {
        switch format {
        case .pdf:
            var themed = template
            themed.includesTranscript = selection.includeTranscript
            themed.includesActionItems = selection.includeActionItems
            themed.includesFollowUps = selection.includeQuestions
            themed.includesShareAppendix = selection.includeSharedScreens
            let html = ReportHTMLRenderer.render(report, template: themed)
            try await ReportPDFRenderer.writePDF(html: html, to: url)
        case .markdown:
            try IntelligenceExport.markdown(report).write(to: url, atomically: true, encoding: .utf8)
        case .csv:
            try IntelligenceExport.csv(report).write(to: url, atomically: true, encoding: .utf8)
        case .json:
            try IntelligenceExport.json(report).write(to: url)
        case .rtf:
            try IntelligenceExport.rtf(report).write(to: url)
        case .xlsx:
            try IntelligenceExport.xlsx(report).write(to: url)
        case .docx:
            try IntelligenceExport.docx(report).write(to: url)
        }
    }

    /// Why a report came out with no pictures. Checked in the order the
    /// pipeline would have failed, so the first true statement is the cause.
    private static func figureDiagnosis(for meeting: Meeting) -> String {
        let frames = meeting.screenFrames
        guard !frames.isEmpty else {
            return "this meeting captured no screen-share frames"
        }
        let missing = frames.filter { frame in
            let url = StorageManager.shared.frameURL(for: meeting.id, relativePath: frame.imagePath)
            return !FileManager.default.fileExists(atPath: url.path)
        }
        if missing.count == frames.count {
            return "all \(frames.count) frame image(s) are missing from disk — the recording folder may have been purged"
        }
        if !missing.isEmpty {
            return "\(missing.count) of \(frames.count) frame image(s) are missing from disk"
        }
        return "\(frames.count) frame(s) exist and are readable — this is unexpected, please report it"
    }

    /// Cached anchoring plan, computed on first export of a given analysis.
    ///
    /// Every failure path here returns nil and the report still exports, with
    /// its figures in the appendix — an unreachable API or an unreadable
    /// response should cost placement, never the document.
    private static func anchorPlan(for meeting: Meeting, report: ReportModel) async -> ReportAnchorPlan? {
        guard let insight = meeting.latestInsight else { return nil }
        guard !report.sections.isEmpty else { return nil }

        let candidates = figureCandidates(for: meeting, report: report)
        guard !candidates.isEmpty else { return nil }

        if let cached = StorageManager.shared.loadReportAnchorPlan(
            for: meeting.id, insightID: insight.id
        ) {
            return cached
        }

        // Double optional: the factory throws on a bad config and returns nil
        // when AI is simply not set up. Both mean "no anchoring, export anyway".
        guard let client = try? await AIClientFactory.makeClient() else { return nil }

        let outlines = report.sections.map { section in
            ReportComposerService.SectionOutline(
                index: section.id,
                title: section.title,
                pointLabels: section.points.map(\.label)
            )
        }

        do {
            let plan = try await ReportComposerService(client: client).anchors(
                sections: outlines,
                frames: candidates,
                insightID: insight.id,
                meetingID: meeting.id
            )
            StorageManager.shared.saveReportAnchorPlan(plan, for: meeting.id)
            return plan
        } catch {
            LogManager.send(
                "Figure anchoring skipped: \(error.localizedDescription)",
                category: .general,
                level: .warning,
                meetingID: meeting.id
            )
            return nil
        }
    }

    /// Only frames the report actually carries can be anchored, so the
    /// catalogue is drawn from the built model rather than from every frame
    /// the meeting captured.
    private static func figureCandidates(
        for meeting: Meeting,
        report: ReportModel
    ) -> [ReportComposerService.FrameCandidate] {
        let present = Set(report.allFigures.map(\.id))
        let byID = Dictionary(
            meeting.screenFrames.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return report.allFigures.compactMap { figure in
            let frame = byID[figure.id]
            guard present.contains(figure.id) else { return nil }
            return ReportComposerService.FrameCandidate(
                id: figure.id,
                formattedTimestamp: figure.formattedTimestamp,
                observation: frame?.observation ?? figure.caption,
                contentType: frame?.contentType?.rawValue,
                entities: frame?.keyEntities ?? []
            )
        }
    }

    private static func savePanelURL(
        for meta: ReportModel.Meta,
        format: IntelligenceExportFormat
    ) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = intelligenceFilename(for: meta, fileExtension: format.fileExtension)
        panel.title = "Export Meeting Intelligence"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// "North Campus Engineering Scope Review_20260818-47m-intel.pdf"
    nonisolated static func suggestedFilename(
        for meta: ReportModel.Meta,
        template _: ReportTemplate,
        fileExtension: String = "pdf"
    ) -> String {
        intelligenceFilename(for: meta, fileExtension: fileExtension)
    }

    nonisolated static func intelligenceFilename(
        for meta: ReportModel.Meta,
        fileExtension: String
    ) -> String {
        exportFilename(
            title: meta.title,
            date: meta.date,
            minutes: meta.durationMinutes,
            kind: "intel",
            fileExtension: fileExtension
        )
    }

    /// `Title_yyyyMMdd-47m-intel.pdf` / `Title_yyyyMMdd-47m-tr.txt`
    nonisolated static func exportFilename(
        title: String,
        date: Date,
        minutes: Int,
        kind: String,
        fileExtension: String
    ) -> String {
        let calendar = Calendar.current
        let day = String(
            format: "%04d%02d%02d",
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
        let ext = fileExtension.hasPrefix(".")
            ? String(fileExtension.dropFirst())
            : fileExtension
        let stem = sanitize("\(title)_\(day)-\(minutes)m-\(kind)")
        return "\(stem).\(ext)"
    }

    nonisolated private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?\"<>|*")
        return name.unicodeScalars
            .filter { !illegal.contains($0) }
            .map(String.init)
            .joined()
    }
}
