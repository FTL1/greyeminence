import Foundation
import UniformTypeIdentifiers

/// Who a dossier is written for. Human-facing pages are filtered; the
/// chatbot prompt pack still carries every stored fact so a later model
/// can work without inventing.
enum DossierAudience: Equatable, Sendable, Hashable {
    case me
    case person(String)
    case boss
    case general

    var fileSlug: String {
        switch self {
        case .me: "me"
        case .person(let name): DossierNaming.slug(name)
        case .boss: "boss"
        case .general: "general"
        }
    }

    var displayName: String {
        switch self {
        case .me: "Me"
        case .person(let name): name
        case .boss: "My boss"
        case .general: "Everyone"
        }
    }
}

enum DossierDepth: String, CaseIterable, Identifiable, Sendable {
    case brief
    case summary
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brief: "Brief"
        case .summary: "Summary"
        case .detailed: "Detailed"
        }
    }
}

enum DossierReportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case txt
    case pdf
    case docx
    case rtf
    case json

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .txt: "Plain text"
        case .pdf: "PDF"
        case .docx: "Word (.docx)"
        case .rtf: "Rich Text (.rtf)"
        case .json: "JSON"
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
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .txt: .plainText
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .rtf: .rtf
        case .json: .json
        }
    }
}

struct DossierRequest: Equatable, Sendable {
    var audience: DossierAudience = .me
    var depth: DossierDepth = .summary
    var includeReport = true
    var reportFormat: DossierReportFormat = .markdown
    var includeTranscript = false
    var includeAudio = false
    var includeScreenshots = false
    var includePromptPackage = true
    var includeSeries = false
    /// Zip of one-pagers: `_general` plus one file per speaker.
    var onePagers = false
}

enum DossierNaming {
    static func slug(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        var slug = String(scalars)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
        return slug.isEmpty ? "person" : slug
    }

    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let x = normalize(a)
        let y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.contains(y) || y.contains(x)
    }

    static func normalize(_ raw: String) -> String {
        raw.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func isMeName(_ name: String, myLabels: [String]) -> Bool {
        let n = normalize(name)
        if n.isEmpty { return false }
        if n == "me" || n == "myself" { return true }
        return myLabels.contains { namesMatch(n, $0) }
    }
}
