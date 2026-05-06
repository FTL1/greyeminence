import SwiftUI
import AppKit

/// Full-window sheet for editing markdown with a formatting toolbar and
/// live rendered preview. Used by `RubricSectionEditorView` for editing
/// the candidate-facing brief, but generic enough that any markdown
/// field could open it via a binding.
struct MarkdownEditorSheet: View {
    @Binding var text: String
    let title: String
    var subtitle: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var showPreview = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            editorAndPreview
        }
        .frame(minWidth: 720, idealWidth: 920, minHeight: 480, idealHeight: 640)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: $showPreview) {
                Label("Preview", systemImage: "eye")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolButton(symbol: "bold", help: "Bold") { wrap("**", "**") }
            toolButton(symbol: "italic", help: "Italic") { wrap("*", "*") }
            toolButton(symbol: "strikethrough", help: "Strikethrough") { wrap("~~", "~~") }
            toolButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Inline code") { wrap("`", "`") }
            Divider().frame(height: 18)
            toolButton(symbol: "h.square", help: "Heading 1") { prefixLine("# ") }
            toolButton(symbol: "h.square.fill", help: "Heading 2") { prefixLine("## ") }
            toolButton(symbol: "list.bullet", help: "Bulleted list") { prefixLine("- ") }
            toolButton(symbol: "list.number", help: "Numbered list") { prefixLine("1. ") }
            toolButton(symbol: "text.quote", help: "Blockquote") { prefixLine("> ") }
            Divider().frame(height: 18)
            toolButton(symbol: "link", help: "Insert link") { wrap("[", "](https://)") }
            toolButton(symbol: "curlybraces.square", help: "Code block") { wrapCodeBlock() }
            Spacer()
            Text("\(text.count) chars")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var editorAndPreview: some View {
        HStack(spacing: 0) {
            MarkdownEditor(text: $text, selectedRange: $selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showPreview {
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var preview: some View {
        ScrollView {
            renderedMarkdown
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var renderedMarkdown: some View {
        if text.isEmpty {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        } else {
            MarkdownView(text: text)
        }
    }

    // MARK: - Toolbar button

    private func toolButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(minWidth: 22, minHeight: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: - Formatting actions

    /// Wrap the current selection (or empty cursor position) with the
    /// given prefix/suffix. After insertion, leaves the selection on the
    /// inserted text so the user can keep typing inside it.
    private func wrap(_ prefix: String, _ suffix: String) {
        let nsText = text as NSString
        let range = clamp(selection, in: nsText)
        let selected = nsText.substring(with: range)
        let replacement = "\(prefix)\(selected)\(suffix)"
        text = nsText.replacingCharacters(in: range, with: replacement)
        let prefixLen = (prefix as NSString).length
        let selectedLen = (selected as NSString).length
        selection = NSRange(location: range.location + prefixLen, length: selectedLen)
    }

    /// Insert the given prefix at the start of the line containing the
    /// caret. If a selection spans multiple lines, prefix each line.
    private func prefixLine(_ p: String) {
        let nsText = text as NSString
        let range = clamp(selection, in: nsText)
        let lineRange = nsText.lineRange(for: range)
        let lineText = nsText.substring(with: lineRange)
        let prefixed = lineText
            .components(separatedBy: "\n")
            .enumerated()
            .map { idx, line -> String in
                // Skip blank trailing element (lineRange ends with \n)
                if idx == lineText.components(separatedBy: "\n").count - 1, line.isEmpty { return line }
                return p + line
            }
            .joined(separator: "\n")
        text = nsText.replacingCharacters(in: lineRange, with: prefixed)
        let pLen = (p as NSString).length
        selection = NSRange(location: range.location + pLen, length: range.length)
    }

    /// Wrap selection (or empty position) in a fenced code block.
    private func wrapCodeBlock() {
        let nsText = text as NSString
        let range = clamp(selection, in: nsText)
        let selected = nsText.substring(with: range)
        let needsLeadingNewline = range.location > 0 && nsText.character(at: range.location - 1) != UInt16(Character("\n").asciiValue ?? 0)
        let prefix = (needsLeadingNewline ? "\n" : "") + "```\n"
        let suffix = "\n```\n"
        let replacement = prefix + selected + suffix
        text = nsText.replacingCharacters(in: range, with: replacement)
        let prefixLen = (prefix as NSString).length
        let selectedLen = (selected as NSString).length
        selection = NSRange(location: range.location + prefixLen, length: selectedLen)
    }

    private func clamp(_ range: NSRange, in nsText: NSString) -> NSRange {
        let length = nsText.length
        let location = max(0, min(range.location, length))
        let maxLen = length - location
        let len = max(0, min(range.length, maxLen))
        return NSRange(location: location, length: len)
    }
}
