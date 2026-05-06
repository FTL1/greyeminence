import SwiftUI
import AppKit

/// Compact panel rendering a section's candidate-facing markdown brief,
/// with Copy and Export-PDF affordances. Used in both the live interview
/// view (active section) and the scorecard view (any section). Hidden
/// when the section has no instructions.
struct CandidateInstructionsPanel: View {
    let sectionTitle: String
    let markdown: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Candidate Brief")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button {
                    PDFExporter.saveMarkdownAsPDF(
                        markdown,
                        suggestedFilename: "\(sectionTitle).pdf",
                        title: sectionTitle
                    )
                } label: {
                    Label("PDF", systemImage: "square.and.arrow.up")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            renderedMarkdown
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var renderedMarkdown: some View {
        MarkdownView(text: markdown, bodyFont: .caption)
            .textSelection(.enabled)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
