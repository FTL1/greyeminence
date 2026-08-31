import AppKit
import Foundation
import UniformTypeIdentifiers

enum TranscriptExportFormat: String, CaseIterable, Identifiable {
    case txt
    case markdown
    case rtf
    case csv
    case xlsx
    case pdf

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .txt: "Plain Text"
        case .markdown: "Markdown"
        case .rtf: "Rich Text (RTF)"
        case .csv: "CSV"
        case .xlsx: "Excel"
        case .pdf: "PDF"
        }
    }

    var fileExtension: String { rawValue == "markdown" ? "md" : rawValue }

    var utType: UTType {
        switch self {
        case .txt: .plainText
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .rtf: .rtf
        case .csv: .commaSeparatedText
        case .xlsx: UTType(filenameExtension: "xlsx") ?? .data
        case .pdf: .pdf
        }
    }
}

struct TranscriptExportLine: Equatable {
    var timestamp: String
    var speaker: String
    var text: String
}

enum TranscriptExportService {
    static let csvHeaders = ["Timestamp", "Speaker", "Text"]

    static func lines(from segments: [TranscriptSegment]) -> [TranscriptExportLine] {
        segments
            .sorted { $0.startTime < $1.startTime }
            .compactMap { segment in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TranscriptExportLine(
                    timestamp: segment.formattedTimestamp,
                    speaker: segment.speaker.displayName,
                    text: text
                )
            }
    }

    static func suggestedFilename(
        title: String,
        date: Date,
        duration: TimeInterval,
        fileExtension: String
    ) -> String {
        let minutes = ReportModelBuilder.durationMinutes(duration)
        return ReportExportService.exportFilename(
            title: title,
            date: date,
            minutes: minutes,
            kind: "tr",
            fileExtension: fileExtension
        )
    }

    static func suggestedFilename(for meeting: Meeting, format: TranscriptExportFormat) -> String {
        suggestedFilename(
            title: meeting.title,
            date: meeting.date,
            duration: meeting.duration,
            fileExtension: format.fileExtension
        )
    }

    static func plainText(
        title: String,
        date: Date,
        durationLabel: String,
        lines: [TranscriptExportLine]
    ) -> String {
        var body = "\(title)\n\(dateLabel(date))  ·  \(durationLabel)\n\n"
        for line in lines {
            body += "\(line.speaker)  \(line.timestamp)\n\(line.text)\n\n"
        }
        return body
    }

    static func markdown(
        title: String,
        date: Date,
        durationLabel: String,
        lines: [TranscriptExportLine]
    ) -> String {
        var body = "# \(title)\n\n\(dateLabel(date)) · \(durationLabel)\n\n"
        for line in lines {
            body += "**\(line.speaker)** · \(line.timestamp)\n\n\(line.text)\n\n"
        }
        return body
    }

    static func csv(lines: [TranscriptExportLine]) -> String {
        let rows = [csvHeaders] + lines.map { [$0.timestamp, $0.speaker, $0.text] }
        return rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func rtf(
        title: String,
        date: Date,
        durationLabel: String,
        lines: [TranscriptExportLine]
    ) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "{", with: "\\{")
                .replacingOccurrences(of: "}", with: "\\}")
        }
        var body = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs22\n"
        body += "\\b \(esc(title))\\b0\\par\n"
        body += "\(esc(dateLabel(date)))  ·  \(esc(durationLabel))\\par\\par\n"
        for line in lines {
            body += "\\b \(esc(line.speaker))\\b0  \(esc(line.timestamp))\\par\n"
            body += "\(esc(line.text))\\par\\par\n"
        }
        body += "}"
        return Data(body.utf8)
    }

    static func xlsx(lines: [TranscriptExportLine]) -> Data {
        let sheetRows = [csvHeaders] + lines.map { [$0.timestamp, $0.speaker, $0.text] }
        return XLSXWriter.data(rows: sheetRows, sheetName: "Transcript")
    }

    static func html(
        title: String,
        date: Date,
        durationLabel: String,
        lines: [TranscriptExportLine]
    ) -> String {
        let rows = lines.map { line in
            """
            <tr>
            <td class="ts">\(htmlEscape(line.timestamp))</td>
            <td class="spk">\(htmlEscape(line.speaker))</td>
            <td>\(htmlEscape(line.text))</td>
            </tr>
            """
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; margin: 36px; color: #111; }
        h1 { font-size: 20px; margin: 0 0 6px; }
        .meta { color: #555; font-size: 12px; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; }
        th, td { border-bottom: 1px solid #ddd; padding: 6px 8px; text-align: left; vertical-align: top; }
        th { background: #f3f3f3; }
        td.ts { width: 52px; white-space: nowrap; color: #666; }
        td.spk { width: 120px; font-weight: 600; }
        </style></head><body>
        <h1>\(htmlEscape(title))</h1>
        <div class="meta">\(htmlEscape(dateLabel(date))) · \(htmlEscape(durationLabel))</div>
        <table><thead><tr><th>Time</th><th>Speaker</th><th>Text</th></tr></thead>
        <tbody>\(rows)</tbody></table>
        </body></html>
        """
    }

    @MainActor
    @discardableResult
    static func presentSavePanel(for meeting: Meeting, format: TranscriptExportFormat) async -> URL? {
        let lines = lines(from: meeting.segments)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format.utType]
        panel.title = "Export Full Transcript"
        panel.nameFieldStringValue = suggestedFilename(for: meeting, format: format)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try await write(
                format: format,
                title: meeting.title,
                date: meeting.date,
                durationLabel: meeting.formattedDuration,
                lines: lines,
                to: url
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch {
            TransientActivityCoordinator.shared.flash("Transcript export failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func clipboardText(for meeting: Meeting) -> String {
        plainText(
            title: meeting.title,
            date: meeting.date,
            durationLabel: meeting.formattedDuration,
            lines: lines(from: meeting.segments)
        )
    }

    @MainActor
    private static func write(
        format: TranscriptExportFormat,
        title: String,
        date: Date,
        durationLabel: String,
        lines: [TranscriptExportLine],
        to url: URL
    ) async throws {
        switch format {
        case .txt:
            try plainText(title: title, date: date, durationLabel: durationLabel, lines: lines)
                .write(to: url, atomically: true, encoding: .utf8)
        case .markdown:
            try markdown(title: title, date: date, durationLabel: durationLabel, lines: lines)
                .write(to: url, atomically: true, encoding: .utf8)
        case .csv:
            try csv(lines: lines).write(to: url, atomically: true, encoding: .utf8)
        case .rtf:
            try rtf(title: title, date: date, durationLabel: durationLabel, lines: lines).write(to: url)
        case .xlsx:
            try xlsx(lines: lines).write(to: url)
        case .pdf:
            try await ReportPDFRenderer.writePDF(
                html: html(title: title, date: date, durationLabel: durationLabel, lines: lines),
                to: url
            )
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?\"<>|*")
        return name.unicodeScalars
            .filter { !illegal.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
