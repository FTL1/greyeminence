import AppKit
import Foundation

/// Copies text to the pasteboard with an HTML flavour alongside the plain
/// one, so apps that accept rich paste render structure instead of showing
/// the markup characters.
///
/// Pasting a summary into Teams was the motivating case: plain text arrives
/// as a wall of lines where "1." is just a digit and "•" is just a bullet
/// glyph — no headings, no list, no emphasis. Teams (like Slack, Outlook and
/// Notes) will take `public.html` and render it properly.
enum RichClipboard {

    /// Write both flavours. Receivers pick the richest they understand, and
    /// anything that only knows plain text still gets readable output — which
    /// is why the plain string has to stand on its own rather than being a
    /// stripped-down afterthought.
    @MainActor
    static func copy(plain: String, html: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.html, .string], owner: nil)
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(plain, forType: .string)
    }

    /// Deliberately spare markup: `<p>`, `<b>` and `<ul>` only.
    ///
    /// Teams accepts a narrow subset of HTML and silently drops the rest, so
    /// anything cleverer — headings, classes, inline styles — either vanishes
    /// or arrives mangled. These four tags survive everywhere worth pasting
    /// into.
    static func summaryHTML(_ sections: [SummarySection]) -> String {
        var parts: [String] = []
        for (index, section) in sections.enumerated() {
            parts.append("<p><b>\(index + 1). \(escape(section.title))</b></p>")

            if let intro = section.intro?.trimmingCharacters(in: .whitespacesAndNewlines),
               !intro.isEmpty {
                parts.append("<p>\(escape(intro))</p>")
            }

            guard !section.points.isEmpty else { continue }
            let items = section.points.map { point -> String in
                let label = point.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = point.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { return "<li>\(escape(detail))</li>" }
                if detail.isEmpty { return "<li><b>\(escape(label))</b></li>" }
                return "<li><b>\(escape(label))</b> — \(escape(detail))</li>"
            }
            parts.append("<ul>\(items.joined())</ul>")
        }
        return parts.joined()
    }

    /// Plain-text form, readable on its own for receivers with no HTML.
    static func summaryPlainText(_ sections: [SummarySection]) -> String {
        sections.enumerated().map { index, section in
            var lines = ["\(index + 1). \(section.title)"]
            if let intro = section.intro?.trimmingCharacters(in: .whitespacesAndNewlines),
               !intro.isEmpty {
                lines.append(intro)
            }
            for point in section.points {
                let label = point.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = point.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(label.isEmpty ? "  • \(detail)" : "  • \(label): \(detail)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// A numbered or bulleted list using only the tags Teams keeps.
    static func listHTML(_ items: [String]) -> String {
        let trimmed = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }
        return "<ul>" + trimmed.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
    }

    /// Summary titles and details are model output and can contain anything.
    /// Ampersand first, or it re-escapes the entities the others produce.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
