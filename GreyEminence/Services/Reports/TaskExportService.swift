import AppKit
import Foundation

enum TaskExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case xlsx = "Excel"
    case rtf = "RTF"
    case pdf = "PDF"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .xlsx: "xlsx"
        case .rtf: "rtf"
        case .pdf: "pdf"
        }
    }
    var contentTypeDescription: String {
        switch self {
        case .csv: "CSV file"
        case .xlsx: "Excel workbook"
        case .rtf: "Rich Text"
        case .pdf: "PDF document"
        }
    }
}

struct TaskExportRow {
    var status: String
    var text: String
    var assignee: String
    var dueDate: String
    var meetingTitle: String
    var meetingDate: String
}

enum TaskExportService {
    static let headers = ["Status", "Action", "Assignee", "Due date", "Meeting", "Meeting date"]

    static func rows(from items: [ActionItem], stalledIDs: Set<UUID> = []) -> [TaskExportRow] {
        items.map { item in
            let status: String
            if item.isDismissed {
                status = "Won't Do"
            } else if item.isCompleted {
                status = "Completed"
            } else if stalledIDs.contains(item.id) {
                status = "Stalled"
            } else {
                status = "Pending"
            }
            return TaskExportRow(
                status: status,
                text: item.text,
                assignee: item.displayAssignee ?? "",
                dueDate: item.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "",
                meetingTitle: item.meeting?.title ?? "",
                meetingDate: item.meeting?.date.formatted(date: .abbreviated, time: .omitted) ?? ""
            )
        }
    }

    static func plainText(rows: [TaskExportRow]) -> String {
        rows.map { row in
            var parts = ["- [\(row.status)] \(row.text)"]
            if !row.assignee.isEmpty { parts.append("(\(row.assignee))") }
            if !row.dueDate.isEmpty { parts.append("due \(row.dueDate)") }
            if !row.meetingTitle.isEmpty { parts.append("— \(row.meetingTitle)") }
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func csv(rows: [TaskExportRow]) -> String {
        let lines = [headers] + rows.map {
            [$0.status, $0.text, $0.assignee, $0.dueDate, $0.meetingTitle, $0.meetingDate]
        }
        return lines.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func rtf(rows: [TaskExportRow]) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "{", with: "\\{")
                .replacingOccurrences(of: "}", with: "\\}")
        }
        var body = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs22\n"
        body += "\\b Pending Actions\\b0\\par\\par\n"
        body += "\\b \(headers.joined(separator: " \\tab "))\\b0\\par\n"
        for row in rows {
            let cells = [row.status, row.text, row.assignee, row.dueDate, row.meetingTitle, row.meetingDate]
            body += esc(cells.joined(separator: " | ")) + "\\par\n"
        }
        body += "}"
        return Data(body.utf8)
    }

    static func xlsx(rows: [TaskExportRow]) -> Data {
        let sheetRows = [headers] + rows.map {
            [$0.status, $0.text, $0.assignee, $0.dueDate, $0.meetingTitle, $0.meetingDate]
        }
        return XLSXWriter.data(rows: sheetRows, sheetName: "Actions")
    }

    static func html(rows: [TaskExportRow]) -> String {
        let header = headers.map { "<th>\(htmlEscape($0))</th>" }.joined()
        let body = rows.map { row in
            let cells = [row.status, row.text, row.assignee, row.dueDate, row.meetingTitle, row.meetingDate]
            return "<tr>" + cells.map { "<td>\(htmlEscape($0))</td>" }.joined() + "</tr>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; margin: 32px; }
        h1 { font-size: 20px; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; }
        th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; vertical-align: top; }
        th { background: #f3f3f3; }
        </style></head><body>
        <h1>Pending Actions</h1>
        <table><thead><tr>\(header)</tr></thead><tbody>\(body)</tbody></table>
        </body></html>
        """
    }

    @MainActor
    static func presentSavePanel(format: TaskExportFormat, rows: [TaskExportRow]) async {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export \(format.contentTypeDescription)"
        panel.nameFieldStringValue = "pending-actions.\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .csv:
                guard let data = csv(rows: rows).data(using: .utf8) else { return }
                try data.write(to: url)
            case .rtf:
                try rtf(rows: rows).write(to: url)
            case .xlsx:
                try xlsx(rows: rows).write(to: url)
            case .pdf:
                try await ReportPDFRenderer.writePDF(html: html(rows: rows), to: url)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            TransientActivityCoordinator.shared.flash("Export failed: \(error.localizedDescription)")
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Store-only ZIP of SpreadsheetML. Excel, Numbers, and Google Sheets open it.
enum XLSXWriter {
    static func data(rows: [[String]], sheetName: String) -> Data {
        data(sheets: [(sheetName, rows)])
    }

    static func data(sheets: [(name: String, rows: [[String]])]) -> Data {
        let named = sheets.enumerated().map { index, sheet in
            (sanitizeSheetName(sheet.name, index: index), sheet.rows)
        }
        var overrides = """
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        """
        var sheetEls = ""
        var rels = ""
        var entries: [(String, Data)] = []
        for (index, sheet) in named.enumerated() {
            let n = index + 1
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            sheetEls += "<sheet name=\"\(xmlEscape(sheet.0))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
            rels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
            entries.append(("xl/worksheets/sheet\(n).xml", Data(worksheetXML(rows: sheet.1).utf8)))
        }
        var all: [(String, Data)] = [
            ("[Content_Types].xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            \(overrides)
            </Types>
            """.utf8)),
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """.utf8)),
            ("xl/workbook.xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>\(sheetEls)</sheets>
            </workbook>
            """.utf8)),
            ("xl/_rels/workbook.xml.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            \(rels)
            </Relationships>
            """.utf8)),
        ]
        all.append(contentsOf: entries)
        return OfficeZip.store(all)
    }

    private static func sanitizeSheetName(_ name: String, index: Int) -> String {
        let illegal = CharacterSet(charactersIn: ":\\/?*[]")
        var cleaned = name.unicodeScalars
            .filter { !illegal.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "Sheet\(index + 1)" }
        if cleaned.count > 31 { cleaned = String(cleaned.prefix(31)) }
        return cleaned
    }

    private static func worksheetXML(rows: [[String]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        """
        for (r, row) in rows.enumerated() {
            xml += "<row r=\"\(r + 1)\">"
            for (c, value) in row.enumerated() {
                let ref = columnName(c) + "\(r + 1)"
                xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func columnName(_ index: Int) -> String {
        var n = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + (n % 26)))) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
