import Foundation

/// Shared front-end for parsing LLM responses that are supposed to be a single
/// JSON object. Strips markdown fences, salvages prose-wrapped JSON by clipping
/// to the outermost `{…}`, and surfaces granular reasons instead of Foundation's
/// opaque NSCocoaErrorDomain 3840 ("data couldn't be read because it is in the
/// wrong format"), which is what users would otherwise see surfaced.
enum AIResponseDecoder {
    static func objectFrom(_ response: String) throws -> [String: Any] {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = cleaned.firstIndex(of: "{"),
           let last = cleaned.lastIndex(of: "}"),
           first < last {
            cleaned = String(cleaned[first...last])
        }

        guard let data = cleaned.data(using: .utf8) else {
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
}
