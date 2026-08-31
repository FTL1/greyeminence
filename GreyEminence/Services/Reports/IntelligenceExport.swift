import Foundation
import UniformTypeIdentifiers

/// What the Meeting Intelligence **Export** menu includes.
struct IntelligenceExportSelection: Equatable, Sendable {
    var includeSummary = true
    var includeActionItems = true
    var includeQuestions = true
    var includeTopics = true
    var includeSharedScreens = true
    var includeTranscript = false
    var dedupeTranscript = true

    var includeAllSections: Bool {
        get {
            includeSummary
                && includeActionItems
                && includeQuestions
                && includeTopics
                && includeSharedScreens
        }
        set {
            includeSummary = newValue
            includeActionItems = newValue
            includeQuestions = newValue
            includeTopics = newValue
            includeSharedScreens = newValue
        }
    }

    var includesAnything: Bool {
        includeSummary
            || includeActionItems
            || includeQuestions
            || includeTopics
            || includeSharedScreens
            || includeTranscript
    }

    func applying(to report: ReportModel) -> ReportModel {
        var next = report
        if includeSummary {
            next = next.keepingSections(Set(report.sections.map(\.id)))
        } else {
            next = next.keepingSections([])
        }
        if !includeActionItems { next.actionItems = [] }
        if !includeQuestions { next.followUpQuestions = [] }
        if !includeTopics { next.topics = [] }
        if !includeSharedScreens { next.shareSessions = [] }
        if !includeTranscript { next.transcript = [] }
        return next
    }
}

enum IntelligenceExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case docx
    case xlsx
    case csv
    case json
    case rtf
    case markdown

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "Word (.docx)"
        case .xlsx: "Excel (.xlsx)"
        case .csv: "CSV"
        case .json: "JSON"
        case .rtf: "Rich Text (.rtf)"
        case .markdown: "Markdown (.md)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        default: rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .xlsx: UTType(filenameExtension: "xlsx") ?? .data
        case .csv: .commaSeparatedText
        case .json: .json
        case .rtf: .rtf
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

/// Renders a filtered `ReportModel` to every Intelligence Export format
/// except PDF (PDF still goes through the HTML → print pipeline).
enum IntelligenceExport {
    static func markdown(_ report: ReportModel) -> String {
        var body = "# \(report.meta.title)\n\n"
        body += "\(dateLabel(report.meta.date)) · \(report.meta.duration)\n\n"
        if !report.meta.attendees.isEmpty {
            body += report.meta.attendees.joined(separator: ", ") + "\n\n"
        }
        for section in report.sections {
            body += "## \(section.title)\n\n"
            if let intro = section.intro, !intro.isEmpty {
                body += intro + "\n\n"
            }
            for point in section.points {
                body += "- **\(point.label)** \(point.detail)\n"
            }
            if !section.points.isEmpty { body += "\n" }
        }
        if !report.actionItems.isEmpty {
            body += "## Action items\n\n"
            for item in report.actionItems {
                let mark = item.isCompleted ? "x" : " "
                let who = item.assignee.map { " (\($0))" } ?? ""
                body += "- [\(mark)] \(item.text)\(who)\n"
            }
            body += "\n"
        }
        if !report.followUpQuestions.isEmpty {
            body += "## Open questions\n\n"
            for question in report.followUpQuestions {
                body += "- \(question)\n"
            }
            body += "\n"
        }
        if !report.topics.isEmpty {
            body += "## Topics\n\n"
            body += report.topics.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !report.shareSessions.isEmpty {
            body += "## Shared screens\n\n"
            for session in report.shareSessions {
                let title = session.windowTitle ?? "Shared screen"
                body += "### \(title) (\(session.startLabel)–\(session.endLabel))\n\n"
                if !session.narrative.isEmpty {
                    body += session.narrative + "\n\n"
                }
            }
        }
        if !report.transcript.isEmpty {
            body += "## Transcript\n\n"
            for line in report.transcript {
                body += "**\(line.speaker)** · \(line.formattedTimestamp)\n\n\(line.text)\n\n"
            }
        }
        return body
    }

    static func rtf(_ report: ReportModel) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "{", with: "\\{")
                .replacingOccurrences(of: "}", with: "\\}")
        }
        var body = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs22\n"
        body += "\\b \(esc(report.meta.title))\\b0\\par\n"
        body += "\(esc(dateLabel(report.meta.date)))  ·  \(esc(report.meta.duration))\\par\\par\n"
        for section in report.sections {
            body += "\\b \(esc(section.title))\\b0\\par\n"
            if let intro = section.intro, !intro.isEmpty {
                body += "\(esc(intro))\\par\n"
            }
            for point in section.points {
                body += "\\b \(esc(point.label))\\b0  \(esc(point.detail))\\par\n"
            }
            body += "\\par\n"
        }
        if !report.actionItems.isEmpty {
            body += "\\b Action items\\b0\\par\n"
            for item in report.actionItems {
                let who = item.assignee.map { " (\($0))" } ?? ""
                body += "\(esc(item.text + who))\\par\n"
            }
            body += "\\par\n"
        }
        if !report.followUpQuestions.isEmpty {
            body += "\\b Open questions\\b0\\par\n"
            for question in report.followUpQuestions {
                body += "\(esc(question))\\par\n"
            }
            body += "\\par\n"
        }
        if !report.topics.isEmpty {
            body += "\\b Topics\\b0\\par\n"
            for topic in report.topics {
                body += "\(esc(topic))\\par\n"
            }
            body += "\\par\n"
        }
        if !report.transcript.isEmpty {
            body += "\\b Transcript\\b0\\par\n"
            for line in report.transcript {
                body += "\\b \(esc(line.speaker))\\b0  \(esc(line.formattedTimestamp))\\par\n"
                body += "\(esc(line.text))\\par\\par\n"
            }
        }
        body += "}"
        return Data(body.utf8)
    }

    static func csv(_ report: ReportModel) -> String {
        var rows: [[String]] = [["Type", "Section", "Field", "Value"]]
        rows.append(["Meta", "", "Title", report.meta.title])
        rows.append(["Meta", "", "Date", dateLabel(report.meta.date)])
        rows.append(["Meta", "", "Duration", report.meta.duration])
        for section in report.sections {
            if let intro = section.intro, !intro.isEmpty {
                rows.append(["Summary", section.title, "Intro", intro])
            }
            for point in section.points {
                rows.append(["Summary", section.title, point.label, point.detail])
            }
        }
        for item in report.actionItems {
            rows.append([
                "Action",
                "",
                item.assignee ?? "",
                item.text,
            ])
        }
        for question in report.followUpQuestions {
            rows.append(["Question", "", "", question])
        }
        for topic in report.topics {
            rows.append(["Topic", "", "", topic])
        }
        for line in report.transcript {
            rows.append(["Transcript", line.speaker, line.formattedTimestamp, line.text])
        }
        return rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func json(_ report: ReportModel) throws -> Data {
        let payload = JSONPayload(
            title: report.meta.title,
            date: ISO8601DateFormatter().string(from: report.meta.date),
            duration: report.meta.duration,
            durationMinutes: report.meta.durationMinutes,
            attendees: report.meta.attendees,
            sourceApp: report.meta.sourceApp,
            summary: report.sections.map {
                JSONSection(
                    title: $0.title,
                    intro: $0.intro,
                    points: $0.points.map { JSONPoint(label: $0.label, detail: $0.detail) }
                )
            },
            actionItems: report.actionItems.map {
                JSONAction(text: $0.text, assignee: $0.assignee, isCompleted: $0.isCompleted)
            },
            followUpQuestions: report.followUpQuestions,
            topics: report.topics,
            sharedScreens: report.shareSessions.map {
                JSONShare(
                    title: $0.windowTitle,
                    start: $0.startLabel,
                    end: $0.endLabel,
                    narrative: $0.narrative
                )
            },
            transcript: report.transcript.map {
                JSONLine(speaker: $0.speaker, timestamp: $0.formattedTimestamp, text: $0.text)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func xlsx(_ report: ReportModel) -> Data {
        var sheets: [(name: String, rows: [[String]])] = []
        var summaryRows: [[String]] = [["Section", "Field", "Value"]]
        summaryRows.append(["", "Title", report.meta.title])
        summaryRows.append(["", "Date", dateLabel(report.meta.date)])
        summaryRows.append(["", "Duration", report.meta.duration])
        for section in report.sections {
            if let intro = section.intro, !intro.isEmpty {
                summaryRows.append([section.title, "Intro", intro])
            }
            for point in section.points {
                summaryRows.append([section.title, point.label, point.detail])
            }
        }
        if summaryRows.count > 1 {
            sheets.append(("Summary", summaryRows))
        }
        if !report.actionItems.isEmpty {
            sheets.append((
                "Actions",
                [["Status", "Action", "Assignee"]] + report.actionItems.map {
                    [$0.isCompleted ? "Done" : "Open", $0.text, $0.assignee ?? ""]
                }
            ))
        }
        if !report.followUpQuestions.isEmpty {
            sheets.append((
                "Questions",
                [["Question"]] + report.followUpQuestions.map { [$0] }
            ))
        }
        if !report.topics.isEmpty {
            sheets.append((
                "Topics",
                [["Topic"]] + report.topics.map { [$0] }
            ))
        }
        if !report.transcript.isEmpty {
            sheets.append((
                "Transcript",
                [["Timestamp", "Speaker", "Text"]] + report.transcript.map {
                    [$0.formattedTimestamp, $0.speaker, $0.text]
                }
            ))
        }
        if sheets.isEmpty {
            sheets.append(("Report", [["Title", report.meta.title]]))
        }
        return XLSXWriter.data(sheets: sheets)
    }

    static func docx(_ report: ReportModel) -> Data {
        var blocks: [DOCXWriter.Block] = [
            .heading(report.meta.title, level: 1),
            .paragraph("\(dateLabel(report.meta.date))  ·  \(report.meta.duration)"),
        ]
        if !report.meta.attendees.isEmpty {
            blocks.append(.paragraph(report.meta.attendees.joined(separator: ", ")))
        }
        for section in report.sections {
            blocks.append(.heading(section.title, level: 2))
            if let intro = section.intro, !intro.isEmpty {
                blocks.append(.paragraph(intro))
            }
            for point in section.points {
                blocks.append(.paragraph("\(point.label)  \(point.detail)"))
            }
        }
        if !report.actionItems.isEmpty {
            blocks.append(.heading("Action items", level: 2))
            for item in report.actionItems {
                let who = item.assignee.map { " (\($0))" } ?? ""
                blocks.append(.paragraph("\(item.text)\(who)"))
            }
        }
        if !report.followUpQuestions.isEmpty {
            blocks.append(.heading("Open questions", level: 2))
            for question in report.followUpQuestions {
                blocks.append(.paragraph(question))
            }
        }
        if !report.topics.isEmpty {
            blocks.append(.heading("Topics", level: 2))
            for topic in report.topics {
                blocks.append(.paragraph(topic))
            }
        }
        if !report.shareSessions.isEmpty {
            blocks.append(.heading("Shared screens", level: 2))
            for session in report.shareSessions {
                let title = session.windowTitle ?? "Shared screen"
                blocks.append(.heading("\(title) (\(session.startLabel)–\(session.endLabel))", level: 3))
                if !session.narrative.isEmpty {
                    blocks.append(.paragraph(session.narrative))
                }
            }
        }
        if !report.transcript.isEmpty {
            blocks.append(.heading("Transcript", level: 2))
            for line in report.transcript {
                blocks.append(.paragraph("\(line.speaker)  \(line.formattedTimestamp)"))
                blocks.append(.paragraph(line.text))
            }
        }
        return DOCXWriter.data(blocks: blocks)
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private struct JSONPayload: Encodable {
        var title: String
        var date: String
        var duration: String
        var durationMinutes: Int
        var attendees: [String]
        var sourceApp: String?
        var summary: [JSONSection]
        var actionItems: [JSONAction]
        var followUpQuestions: [String]
        var topics: [String]
        var sharedScreens: [JSONShare]
        var transcript: [JSONLine]
    }

    private struct JSONSection: Encodable {
        var title: String
        var intro: String?
        var points: [JSONPoint]
    }

    private struct JSONPoint: Encodable {
        var label: String
        var detail: String
    }

    private struct JSONAction: Encodable {
        var text: String
        var assignee: String?
        var isCompleted: Bool
    }

    private struct JSONShare: Encodable {
        var title: String?
        var start: String
        var end: String
        var narrative: String
    }

    private struct JSONLine: Encodable {
        var speaker: String
        var timestamp: String
        var text: String
    }
}
