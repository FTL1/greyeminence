import Foundation

/// Citation handling for Ask answers.
///
/// The model is asked to cite snippets as `[3]` or `[3, 7]`. Two things need
/// to happen to that text: the numbers get pulled out (so the sources panel
/// can show which snippets actually earned their place in the answer), and
/// the brackets get rewritten as markdown links so tapping one selects the
/// snippet. `MarkdownText` renders inline markdown, so a link is all it takes.
enum AskCitations {
    /// URL scheme for a citation tap. Deliberately app-private — nothing
    /// outside `AskChatView`'s `openURL` handler should resolve it.
    static let scheme = "greyeminence-ask-source"

    static func url(forNumber number: Int) -> URL? {
        URL(string: "\(scheme)://source/\(number)")
    }

    static func number(fromURL url: URL) -> Int? {
        guard url.scheme == scheme else { return nil }
        return Int(url.lastPathComponent)
    }

    /// Matches `[3]` and `[3, 7]` / `[3,7]` but not `[link](url)` markdown or
    /// prose brackets — the contents must be digits and separators only.
    private static let citationRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#)
    }()

    /// Every number cited in `answer`, in first-appearance order.
    static func cited(in answer: String) -> [Int] {
        var seen = Set<Int>()
        var ordered: [Int] = []
        for numbers in matches(in: answer).map(\.numbers) {
            for number in numbers where !seen.contains(number) {
                seen.insert(number)
                ordered.append(number)
            }
        }
        return ordered
    }

    /// Rewrite bracket citations as markdown links. `known` gates the
    /// rewrite: a hallucinated `[99]` with no snippet behind it stays plain
    /// text rather than becoming a link that goes nowhere.
    static func linkify(_ answer: String, known: Set<Int>) -> String {
        var output = answer
        // Replace back-to-front so earlier ranges stay valid.
        for match in matches(in: answer).reversed() {
            let usable = match.numbers.filter { known.contains($0) }
            guard usable.count == match.numbers.count, !usable.isEmpty else { continue }
            let linked = usable
                .map { number in
                    guard let url = url(forNumber: number) else { return "[\(number)]" }
                    return "[\(number)](\(url.absoluteString))"
                }
                .joined(separator: " ")
            guard let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: linked)
        }
        return output
    }

    private struct Match {
        let range: NSRange
        let numbers: [Int]
    }

    private static func matches(in text: String) -> [Match] {
        let full = NSRange(text.startIndex..., in: text)
        return citationRegex.matches(in: text, range: full).compactMap { result in
            guard let inner = Range(result.range(at: 1), in: text) else { return nil }
            let numbers = text[inner]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !numbers.isEmpty else { return nil }
            return Match(range: result.range, numbers: numbers)
        }
    }
}
