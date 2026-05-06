import Foundation
import PDFKit
import AppKit

/// Best-effort text extraction from candidate resume files. Used to seed
/// the live interview AI prompt with candidate background — the AI sees
/// the resume text as a "Candidate Background" prelude alongside the
/// rubric and rolling transcript.
///
/// Supported sources:
///   - PDF: PDFKit's per-page string concatenation
///   - RTF / RTFD: NSAttributedString
///   - Plain text / Markdown: UTF-8 decode of the file's contents
///
/// DOC and DOCX are deliberately out of scope — neither has a native
/// macOS parser and pulling in a third-party library for one input
/// type isn't worth the dependency cost. Users on Word can export
/// to PDF and re-attach.
enum ResumeTextExtractor {
    /// Maximum characters returned. Caps prompt cost at a known ceiling
    /// regardless of how long the resume is. ~8K chars ≈ ~2K tokens —
    /// roughly two pages of dense text. Fine for the typical resume;
    /// truncation is silent on the assumption that the most relevant
    /// content is in the first two pages.
    static let maxCharacters = 8_000

    /// Returns nil when the file can't be read or contains no extractable
    /// text. Truncates with an "…" ellipsis when over `maxCharacters`.
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        let raw: String?
        switch ext {
        case "pdf":
            raw = extractPDF(at: url)
        case "rtf", "rtfd":
            raw = extractRTF(at: url)
        case "txt", "md", "markdown":
            raw = try? String(contentsOf: url, encoding: .utf8)
        default:
            raw = (try? String(contentsOf: url, encoding: .utf8))
                ?? extractRTF(at: url)
        }
        guard let raw, !raw.isEmpty else { return nil }
        return truncated(raw)
    }

    private static func extractPDF(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var pieces: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                pieces.append(text)
            }
        }
        let joined = pieces.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func extractRTF(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attributed?.string
    }

    private static func truncated(_ text: String) -> String {
        // Normalize whitespace runs so the truncation cap measures actual
        // content, not page-break padding. Multiple newlines collapse to
        // two; multiple spaces collapse to one.
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = collapsed.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let normalized = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)

        if normalized.count <= maxCharacters { return normalized }
        let prefix = normalized.prefix(maxCharacters)
        return "\(prefix)…\n[resume truncated to first \(maxCharacters) characters]"
    }
}
