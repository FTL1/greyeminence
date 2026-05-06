import SwiftUI

/// Block-aware SwiftUI markdown renderer. We can't use
/// `Text(AttributedString(markdown:options:.init(interpretedSyntax: .full)))`
/// because it concatenates block elements (headings, paragraphs, lists)
/// into a single attributed run with no visual separation — the
/// rendered output ends up as one long blob. This view splits the
/// source into blocks, classifies each, and renders them with
/// appropriate spacing and styling.
///
/// Inline markdown (bold, italic, links, inline code) is still parsed
/// per-block via `AttributedString(markdown:)` with the inline-only
/// syntax option.
struct MarkdownView: View {
    let text: String
    var bodyFont: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case blockquote(String)
        case codeBlock(String)
        case rule
    }

    private func parseBlocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                i += 1
                var content: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    content.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // consume closing fence
                blocks.append(.codeBlock(content.joined(separator: "\n")))
                continue
            }

            // Heading (#, ##, ###)
            if let level = headingLevel(of: trimmed) {
                let stripped = trimmed.drop { $0 == "#" }.drop { $0 == " " }
                blocks.append(.heading(level: level, text: String(stripped)))
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.rule)
                i += 1
                continue
            }

            // Bullet list
            if isBullet(trimmed) {
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let lt = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(lt.dropFirst(2)))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list
            if isNumbered(trimmed) {
                var items: [String] = []
                while i < lines.count, let stripped = stripNumberedPrefix(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(stripped)
                    i += 1
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quote: [String] = []
                while i < lines.count {
                    let lt = lines[i].trimmingCharacters(in: .whitespaces)
                    if lt.hasPrefix("> ") {
                        quote.append(String(lt.dropFirst(2)))
                    } else if lt == ">" {
                        quote.append("")
                    } else { break }
                    i += 1
                }
                blocks.append(.blockquote(quote.joined(separator: "\n")))
                continue
            }

            // Blank line — skip without emitting
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph: gather contiguous non-blank, non-special lines.
            // Hard line breaks within a paragraph are flattened to spaces
            // (commonmark behavior).
            var paragraph: [String] = []
            while i < lines.count {
                let lt = lines[i].trimmingCharacters(in: .whitespaces)
                if lt.isEmpty { break }
                if headingLevel(of: lt) != nil { break }
                if isBullet(lt) || isNumbered(lt) || lt.hasPrefix("> ") { break }
                if lt.hasPrefix("```") { break }
                if lt == "---" || lt == "***" || lt == "___" { break }
                paragraph.append(lt)
                i += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
            }
        }
        return blocks
    }

    private func headingLevel(of line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private func isNumbered(_ line: String) -> Bool {
        stripNumberedPrefix(line) != nil
    }

    private func stripNumberedPrefix(_ line: String) -> String? {
        // Match leading "<digits>. " or "<digits>) "
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber {
            idx = line.index(after: idx)
        }
        guard idx > line.startIndex,
              idx < line.endIndex,
              line[idx] == "." || line[idx] == ")" else { return nil }
        let next = line.index(after: idx)
        guard next < line.endIndex, line[next] == " " else { return nil }
        return String(line[line.index(after: next)...])
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .padding(.top, level == 1 ? 4 : 2)
        case .paragraph(let text):
            inlineText(text)
                .font(bodyFont)
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(bodyFont)
                        inlineText(item)
                            .font(bodyFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .foregroundStyle(.secondary)
                            .font(bodyFont.monospacedDigit())
                        inlineText(item)
                            .font(bodyFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
                    .italic()
                    .font(bodyFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        case .rule:
            Divider()
                .padding(.vertical, 2)
        }
    }

    /// Render inline markdown (bold, italic, code, links). Keeps the
    /// source whitespace so soft-wrap inside paragraphs works.
    private func inlineText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.weight(.bold)
        case 2: .title2.weight(.bold)
        case 3: .title3.weight(.semibold)
        case 4: .headline
        default: .body.weight(.semibold)
        }
    }
}
