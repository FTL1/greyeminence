import Foundation

/// D&D-style attribute panel derived from a candidate's resume. Stored
/// as JSON on `Candidate.characterSheetJSON` because the shape evolves
/// with prompt iteration and we don't want to migrate the schema every
/// time we tweak a field. `Codable` for serialization, `Sendable` so it
/// can be passed across the AI service actor boundary.
struct CharacterSheet: Codable, Sendable, Equatable {
    let className: String
    let classDescription: String?
    let level: Int
    /// AI-supplied reasoning for the chosen level. Older sheets generated
    /// before this field shipped will decode with `nil` and the UI hides
    /// the reasoning row.
    let levelReasoning: String?
    let attributes: [DnDAttribute]
    let specializations: [String]
    let notableFeats: [String]

    enum CodingKeys: String, CodingKey {
        case className = "class_name"
        case classDescription = "class_description"
        case level
        case levelReasoning = "level_reasoning"
        case attributes
        case specializations
        case notableFeats = "notable_feats"
    }
}

/// One of the six classic D&D ability scores, repurposed for engineering
/// signals. Standard D&D values run 3–18 for player characters; we cap
/// at 18 here because the resume rarely substantiates higher.
struct DnDAttribute: Codable, Sendable, Equatable, Identifiable {
    var id: String { abbreviation }
    let name: String
    let abbreviation: String
    let value: Int
    let descriptor: String
    /// AI-supplied per-candidate justification for the chosen value.
    /// Older sheets decode with `nil`.
    let reasoning: String?
}

extension CharacterSheet {
    /// Decode from the JSON string stored on `Candidate.characterSheetJSON`.
    /// Returns nil on missing/malformed input — callers fall back to
    /// "no character sheet yet" UI.
    static func fromJSON(_ json: String?) -> CharacterSheet? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CharacterSheet.self, from: data)
    }

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
