import Foundation

/// What the user chose in the export sheet.
///
/// Separate from `ReportTemplate` because these are per-export decisions —
/// which parts of *this* meeting to include — while a template describes how
/// any report should look. The template supplies the defaults; these override
/// them for one export.
struct ReportExportOptions: Sendable, Equatable {
    var templateID: String
    /// Summary sections to keep, by `ReportModel.Section.id`. Everything is
    /// selected by default: leaving a section out is a deliberate act.
    var sectionIDs: Set<Int>
    var includesActionItems: Bool
    var includesFollowUps: Bool
    var includesSharedScreens: Bool
    var includesTranscript: Bool
    var figuresAtEnd: Bool

    /// True when nothing at all is ticked — the export sheet disables its
    /// button on this rather than producing an empty document.
    var isEmpty: Bool {
        sectionIDs.isEmpty
            && !includesActionItems
            && !includesFollowUps
            && !includesSharedScreens
            && !includesTranscript
    }

    /// The chosen template with the per-export switches applied.
    var template: ReportTemplate {
        var template = ReportTemplateCatalog.template(id: templateID)
        template.includesActionItems = includesActionItems
        template.includesFollowUps = includesFollowUps
        template.includesShareAppendix = includesSharedScreens
        template.includesTranscript = includesTranscript
        template.figuresAtEnd = figuresAtEnd
        return template
    }

    /// Everything on, which is what the sheet opens with.
    static func defaults(
        templateID: String,
        sectionIDs: Set<Int>,
        figuresAtEnd: Bool,
        includesTranscript: Bool = false
    ) -> ReportExportOptions {
        ReportExportOptions(
            templateID: templateID,
            sectionIDs: sectionIDs,
            includesActionItems: true,
            includesFollowUps: true,
            includesSharedScreens: true,
            // Off unless asked for: a transcript is many pages and turns a
            // summary report into a record.
            includesTranscript: includesTranscript,
            figuresAtEnd: figuresAtEnd
        )
    }
}
