import Foundation

/// Shared front-end for parsing LLM responses that are supposed to be a single
/// JSON object. Strips markdown fences, salvages prose-wrapped JSON by clipping
/// to the outermost `{…}`, and — critically — recovers from responses that were
/// truncated mid-object because the model hit `max_tokens`. Surfaces granular
/// reasons instead of Foundation's opaque NSCocoaErrorDomain 3840 ("data
/// couldn't be read because it is in the wrong format"), which is what users
/// would otherwise see surfaced.
enum AIResponseDecoder {
    static func objectFrom(_ response: String) throws -> [String: Any] {
        let cleaned = stripFences(response)
        guard let firstBrace = cleaned.firstIndex(of: "{") else {
            throw AIParseError.invalidJSON(reason: "no JSON object in response")
        }
        let body = String(cleaned[firstBrace...])

        // 1. Happy path: clip to the outermost matching close brace and parse.
        let clipped: String
        if let last = body.lastIndex(of: "}") {
            clipped = String(body[...last])
        } else {
            clipped = body
        }
        if let obj = try? parse(clipped) {
            return obj
        }

        // 2. Salvage a truncated response by balancing the open braces/brackets.
        //    Handles the common case where generation stopped mid-string or
        //    mid-array (max_tokens), keeping everything that completed.
        if let repaired = balanceTruncated(body), let obj = try? parse(repaired) {
            LogManager.send(
                "AI response was truncated (likely max_tokens) — salvaged partial JSON via brace-balancing",
                category: .ai,
                level: .warning
            )
            return obj
        }

        // 3. Harder truncation (e.g. cut on a dangling key): drop the trailing
        //    incomplete fragment back to the last complete value, then balance.
        if let repaired = dropTrailingFragment(body), let obj = try? parse(repaired) {
            LogManager.send(
                "AI response was truncated — salvaged partial JSON by dropping the trailing fragment",
                category: .ai,
                level: .warning
            )
            return obj
        }

        // 4. Nothing worked — surface the original parser error with its reason.
        return try parse(clipped)
    }

    // MARK: - Helpers

    private static func stripFences(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parse(_ s: String) throws -> [String: Any] {
        guard let data = s.data(using: .utf8), !data.isEmpty else {
            throw AIParseError.invalidJSON(reason: "empty response")
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIParseError.invalidJSON(reason: error.localizedDescription)
        }
        guard let json = raw as? [String: Any] else {
            throw AIParseError.invalidJSON(reason: "top-level not an object")
        }
        return json
    }

    /// Close any strings/arrays/objects left open by a truncated response.
    /// Returns `nil` when there's nothing to repair (already balanced).
    private static func balanceTruncated(_ s: String) -> String? {
        var stack: [Character] = []
        var inString = false
        var escaped = false

        for ch in s {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}": if stack.last == "}" { stack.removeLast() }
            case "]": if stack.last == "]" { stack.removeLast() }
            default: break
            }
        }

        guard inString || !stack.isEmpty else { return nil }

        var result = s
        if inString {
            result.append("\"")
        }
        trimTrailingWhitespace(&result)
        // A dangling separator/colon would make the closers invalid.
        if let last = result.last {
            if last == "," {
                result.removeLast()
                trimTrailingWhitespace(&result)
            } else if last == ":" {
                result.append("null")
            }
        }
        for closer in stack.reversed() {
            result.append(closer)
        }
        return result
    }

    /// Truncate to the last complete value (last `}` or `]` outside a string),
    /// then balance. Used when `balanceTruncated` produced something still
    /// invalid — e.g. the response was cut right after a key with no value.
    private static func dropTrailingFragment(_ s: String) -> String? {
        var inString = false
        var escaped = false
        var cut: String.Index?
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "}" || ch == "]" {
                cut = idx
            }
            idx = s.index(after: idx)
        }
        guard let cut else { return nil }
        let truncated = String(s[...cut])
        return balanceTruncated(truncated) ?? truncated
    }

    private static func trimTrailingWhitespace(_ s: inout String) {
        while let last = s.last, last == " " || last == "\n" || last == "\t" || last == "\r" {
            s.removeLast()
        }
    }
}
