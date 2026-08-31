import Foundation

enum DossierBlock: Equatable {
    case heading(String, Int)
    case paragraph(String)
    case bullet(String)
    case quote(speaker: String, time: String, text: String)
}

enum DossierRenderer {
    static func blocks(
        snapshots: [DossierMeetingSnapshot],
        audience: DossierAudience,
        depth: DossierDepth,
        includeTranscript: Bool
    ) -> [DossierBlock] {
        var blocks: [DossierBlock] = []
        let heading = snapshots.count == 1
            ? snapshots[0].title
            : "\(snapshots[0].title) — \(snapshots.count) meetings"
        blocks.append(.heading(heading, 1))
        var meta = "Audience: \(audience.displayName)  ·  \(depth.label)"
        if snapshots.count == 1 {
            meta += "  ·  \(dateLabel(snapshots[0].date))  ·  \(snapshots[0].durationLabel)"
        }
        blocks.append(.paragraph(meta))
        blocks.append(.paragraph(
            "This dossier copies stored meeting intelligence and transcript text. It does not add facts."
        ))

        for snapshot in snapshots {
            if snapshots.count > 1 {
                blocks.append(.heading(snapshot.title, 2))
                blocks.append(.paragraph("\(dateLabel(snapshot.date))  ·  \(snapshot.durationLabel)"))
            }
            if let purpose = DossierFacts.purpose(from: snapshot) {
                blocks.append(.heading("Purpose", snapshots.count > 1 ? 3 : 2))
                blocks.append(.paragraph(purpose))
            }

            let sections = DossierFacts.capSummary(
                SummarySection.parse(snapshot.summaryJSON) ?? [],
                depth: depth
            )
            if !sections.isEmpty {
                blocks.append(.heading("Summary", snapshots.count > 1 ? 3 : 2))
                for section in sections {
                    blocks.append(.heading(section.title, snapshots.count > 1 ? 4 : 3))
                    if let intro = section.intro, !intro.isEmpty {
                        blocks.append(.paragraph(intro))
                    }
                    for point in section.points {
                        blocks.append(.bullet("\(point.label) — \(point.detail)"))
                    }
                }
            }

            let actions = DossierFacts.capList(
                DossierFacts.filterActions(snapshot.actionItems, audience: audience, myLabels: snapshot.myLabels),
                depth: depth
            )
            if !actions.isEmpty {
                blocks.append(.heading("Action items", snapshots.count > 1 ? 3 : 2))
                for item in actions {
                    var line = item.text
                    if let who = item.assignee, !who.isEmpty { line += " (\(who))" }
                    if item.isCompleted { line += " [done]" }
                    blocks.append(.bullet(line))
                    if depth == .detailed, let quote = item.sourceQuote, !quote.isEmpty {
                        blocks.append(.quote(speaker: item.assignee ?? "", time: "", text: quote))
                    }
                }
            }

            let questions = DossierFacts.capList(
                DossierFacts.followUps(snapshot.followUps, audience: audience),
                depth: depth
            )
            if !questions.isEmpty {
                blocks.append(.heading("Open questions", snapshots.count > 1 ? 3 : 2))
                for question in questions {
                    blocks.append(.bullet(question))
                }
            }

            if depth == .detailed, !snapshot.topics.isEmpty {
                blocks.append(.heading("Topics", snapshots.count > 1 ? 3 : 2))
                blocks.append(.paragraph(snapshot.topics.joined(separator: ", ")))
            }

            if depth == .detailed {
                let lines = DossierFacts.filterTranscript(
                    snapshot.transcript,
                    audience: audience,
                    myLabels: snapshot.myLabels
                )
                let quotes = DossierFacts.speakerQuotes(from: lines, limit: 8)
                if !quotes.isEmpty {
                    blocks.append(.heading("Verbatim excerpts", snapshots.count > 1 ? 3 : 2))
                    for line in quotes {
                        blocks.append(.quote(speaker: line.speaker, time: line.timestamp, text: line.text))
                    }
                }
            }

            if includeTranscript {
                let lines = DossierFacts.filterTranscript(
                    snapshot.transcript,
                    audience: audience,
                    myLabels: snapshot.myLabels
                )
                if !lines.isEmpty {
                    blocks.append(.heading("Transcript", snapshots.count > 1 ? 3 : 2))
                    for line in lines {
                        blocks.append(.quote(speaker: line.speaker, time: line.timestamp, text: line.text))
                    }
                }
            }
        }
        return blocks
    }

    static func markdown(_ blocks: [DossierBlock]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .heading(let text, let level):
                body += String(repeating: "#", count: max(1, min(level, 6))) + " \(text)\n\n"
            case .paragraph(let text):
                body += text + "\n\n"
            case .bullet(let text):
                body += "- \(text)\n"
            case .quote(let speaker, let time, let text):
                var prefix = speaker
                if !time.isEmpty { prefix += prefix.isEmpty ? time : " · \(time)" }
                if !prefix.isEmpty { body += "> **\(prefix)**\n" }
                body += "> \(text)\n\n"
            }
            if case .bullet = block {
                continue
            }
        }
        return closeLists(body)
    }

    static func plainText(_ blocks: [DossierBlock]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .heading(let text, _):
                body += text.uppercased() + "\n\n"
            case .paragraph(let text):
                body += text + "\n\n"
            case .bullet(let text):
                body += "• \(text)\n"
            case .quote(let speaker, let time, let text):
                var prefix = speaker
                if !time.isEmpty { prefix += prefix.isEmpty ? time : " \(time)" }
                if !prefix.isEmpty { body += "[\(prefix)] " }
                body += text + "\n\n"
            }
        }
        return body
    }

    static func html(_ blocks: [DossierBlock], title: String) -> String {
        var inner = ""
        var inList = false
        func closeList() {
            if inList {
                inner += "</ul>\n"
                inList = false
            }
        }
        for block in blocks {
            switch block {
            case .heading(let text, let level):
                closeList()
                let tag = "h\(max(1, min(level, 6)))"
                inner += "<\(tag)>\(escape(text))</\(tag)>\n"
            case .paragraph(let text):
                closeList()
                inner += "<p>\(escape(text))</p>\n"
            case .bullet(let text):
                if !inList {
                    inner += "<ul>\n"
                    inList = true
                }
                inner += "<li>\(escape(text))</li>\n"
            case .quote(let speaker, let time, let text):
                closeList()
                var cite = speaker
                if !time.isEmpty { cite += cite.isEmpty ? time : " · \(time)" }
                inner += "<blockquote>"
                if !cite.isEmpty { inner += "<strong>\(escape(cite))</strong><br>" }
                inner += "\(escape(text))</blockquote>\n"
            }
        }
        closeList()
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        @page { size: letter; margin: 0.75in; }
        body { font: 12pt/1.45 -apple-system, Helvetica, sans-serif; color: #111; }
        h1 { font-size: 18pt; } h2 { font-size: 14pt; } h3 { font-size: 12pt; }
        blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 12px; color: #333; }
        li { margin: 4px 0; }
        </style></head><body>\(inner)</body></html>
        """
    }

    static func docx(_ blocks: [DossierBlock]) -> Data {
        var parts: [DOCXWriter.Block] = []
        for block in blocks {
            switch block {
            case .heading(let text, let level):
                parts.append(.heading(text, level: max(1, min(level, 3))))
            case .paragraph(let text):
                parts.append(.paragraph(text))
            case .bullet(let text):
                parts.append(.paragraph("• \(text)"))
            case .quote(let speaker, let time, let text):
                var prefix = speaker
                if !time.isEmpty { prefix += prefix.isEmpty ? time : " · \(time)" }
                let line = prefix.isEmpty ? text : "\(prefix): \(text)"
                parts.append(.paragraph(line))
            }
        }
        return DOCXWriter.data(blocks: parts)
    }

    static func rtf(_ blocks: [DossierBlock]) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "{", with: "\\{")
                .replacingOccurrences(of: "}", with: "\\}")
        }
        var body = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs22\n"
        for block in blocks {
            switch block {
            case .heading(let text, _):
                body += "\\b \(esc(text))\\b0\\par\\par\n"
            case .paragraph(let text):
                body += "\(esc(text))\\par\\par\n"
            case .bullet(let text):
                body += "\\bullet  \(esc(text))\\par\n"
            case .quote(let speaker, let time, let text):
                var prefix = speaker
                if !time.isEmpty { prefix += prefix.isEmpty ? time : " · \(time)" }
                if !prefix.isEmpty { body += "\\i \(esc(prefix))\\i0\\par\n" }
                body += "\(esc(text))\\par\\par\n"
            }
        }
        body += "}"
        return Data(body.utf8)
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func closeLists(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "(\n- [^\\n]+)\\n#", with: "$1\n\n#", options: .regularExpression)
    }
}
