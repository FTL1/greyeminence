import SwiftUI

/// Renders the subset of Markdown that LLM answers commonly produce — ATX
/// headings, bullet / numbered lists, blockquotes, and inline emphasis (bold,
/// italic, code, links) — as native SwiftUI views.
///
/// SwiftUI's `Text` only renders *inline* markdown; block-level structure like
/// `## headers` and `- lists` shows up as literal characters. This splits the
/// source into blocks and renders each, using `AttributedString` for the inline
/// styling within a block.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Self.inline(text)
                .font(Self.headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Self.inline(text)
            }

        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Self.inline(text)
            }

        case .quote(let text):
            Self.inline(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3)
                }

        case .paragraph(let text):
            Self.inline(text)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }

    /// Render inline markdown (bold/italic/code/links) within a single block,
    /// falling back to the raw string if parsing fails.
    private static func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }
}

/// One block of parsed markdown.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case numbered(marker: String, text: String)
    case quote(text: String)
    case paragraph(text: String)

    /// Split markdown into blocks. Consecutive plain lines are joined into one
    /// paragraph (markdown semantics); a blank line ends a paragraph.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(text: paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if let bullet = parseBullet(line) {
                flushParagraph()
                blocks.append(.bullet(text: bullet))
            } else if let numbered = parseNumbered(line) {
                flushParagraph()
                blocks.append(numbered)
            } else if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseNumbered(_ line: String) -> MarkdownBlock? {
        // e.g. "1. text" / "12) text"
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = line.dropFirst(digits.count)
        guard let sep = afterDigits.first, sep == "." || sep == ")",
              afterDigits.dropFirst().first == " " else { return nil }
        let text = afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return .numbered(marker: "\(digits).", text: text)
    }
}
