import Foundation

/// A meeting report, fully detached from SwiftData.
///
/// Everything downstream of this type — HTML rendering, templating, PDF
/// output, the future Teams and publish paths — is pure and testable without
/// a `ModelContext`, a `Meeting`, or AppKit. Figures carry their image bytes
/// so a report can be rendered long after the builder ran, on any thread.
struct ReportModel: Sendable, Equatable {
    var meta: Meta
    var sections: [Section]
    var actionItems: [ActionItem]
    var followUpQuestions: [String]
    var topics: [String]
    /// Share sessions that produced a narrative, for the appendix. Figures
    /// anchored into `sections` are not repeated here.
    var shareSessions: [ShareSession]
    /// Populated only when the template asks for it — transcripts are long
    /// and most reports should not carry one.
    var transcript: [TranscriptLine]

    struct Meta: Sendable, Equatable {
        var title: String
        var date: Date
        var duration: String
        /// Whole minutes, for export filenames. 0 when the meeting has no clock.
        var durationMinutes: Int = 0
        var attendees: [String]
        /// "Microsoft Teams", "Zoom", … when the meeting knows where it came from.
        var sourceApp: String?
        var generatedAt: Date
    }

    /// One summary section, mirroring `SummarySection` from the analysis
    /// pipeline, plus the figures anchored to it.
    struct Section: Sendable, Equatable, Identifiable {
        var id: Int
        var title: String
        var intro: String?
        var points: [Point]
        var figures: [Figure]
    }

    struct Point: Sendable, Equatable {
        var label: String
        var detail: String
    }

    /// A screenshot placed in the report. `imageData` is already downscaled
    /// and JPEG-encoded — the renderer only base64s it.
    struct Figure: Sendable, Equatable, Identifiable {
        var id: UUID
        /// Elapsed seconds since recording start.
        var timestamp: TimeInterval
        /// "m:ss", matching how timestamps read everywhere else in the app.
        var formattedTimestamp: String
        var caption: String
        var imageData: Data
        var windowTitle: String?
        /// The section this figure was judged to evidence, if any. Retained
        /// even when the figure prints in the appendix rather than inside the
        /// section, because that is exactly when a reader needs the link back
        /// to the prose it belongs to.
        var sectionIndex: Int?
        var sectionTitle: String?
    }

    struct ActionItem: Sendable, Equatable {
        var text: String
        var assignee: String?
        var isCompleted: Bool
    }

    struct ShareSession: Sendable, Equatable, Identifiable {
        var id: UUID
        var windowTitle: String?
        var startLabel: String
        var endLabel: String
        var narrative: String
        var keyMoments: [KeyMoment]
        /// Figures belonging to this session rather than to a summary
        /// section. Until figure anchoring lands, everything worth showing
        /// arrives here; afterwards this holds only what no section claimed.
        var figures: [Figure]
    }

    struct KeyMoment: Sendable, Equatable {
        var label: String
        var formattedTimestamp: String
    }

    struct TranscriptLine: Sendable, Equatable {
        var speaker: String
        var formattedTimestamp: String
        var text: String
    }

    /// True when there is genuinely nothing to render — the export UI uses
    /// this to explain itself rather than producing an empty page.
    var isEmpty: Bool {
        sections.isEmpty
            && actionItems.isEmpty
            && followUpQuestions.isEmpty
            && topics.isEmpty
            && shareSessions.isEmpty
            && transcript.isEmpty
    }

    /// Every figure in document order — anchored ones first, then the
    /// appendix — so figure numbering is stable and matches reading order.
    var allFigures: [Figure] {
        sections.flatMap(\.figures) + shareSessions.flatMap(\.figures)
    }
}
