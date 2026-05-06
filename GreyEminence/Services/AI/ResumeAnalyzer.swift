import Foundation

/// Result of running a resume through the AI analyzer. The summary
/// replaces the raw 8K-char dump in the live interview prompt; the
/// character sheet drives the candidate detail UI.
struct ResumeAnalysis: Codable, Sendable {
    let summary: String
    let characterSheet: CharacterSheet

    enum CodingKeys: String, CodingKey {
        case summary
        case characterSheet = "character_sheet"
    }
}

/// One-shot resume analyzer. Called in the background when a candidate
/// uploads or replaces their resume; produces a compact summary plus a
/// D&D-style character sheet. Stays an enum (no actor) because there's
/// no shared state — each call is independent.
enum ResumeAnalyzer {
    /// Returns nil when the AI client isn't configured or the response
    /// can't be parsed. Caller is expected to fall back to using the raw
    /// truncated text in the prompt context.
    static func analyze(resumeText: String, candidateName: String) async throws -> ResumeAnalysis? {
        guard let client = try? await AIClientFactory.makeClient() else { return nil }
        let prompt = buildPrompt(resumeText: resumeText, candidateName: candidateName)

        let response = try await AIRetry.run(label: "resumeAnalysis") {
            try await withTimeout(seconds: 60) {
                try await client.sendMessage(system: systemPrompt, userContent: prompt)
            }
        }
        return parse(response)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    You analyze candidate resumes for an interview prep dossier. Output \
    structured JSON only — no prose, no markdown, no commentary. Stay \
    grounded in what the resume actually says; do not embellish or \
    invent achievements. When a field has no resume support, default \
    conservatively (level 5, attribute value 10).
    """

    private static func buildPrompt(resumeText: String, candidateName: String) -> String {
        """
        Produce a concise summary plus a D&D-style "character sheet" for \
        the candidate. Output ONLY valid JSON matching this schema exactly:

        {
          "summary": "200–500 char summary covering: years of experience, key technical domains, notable shipped projects/scope, leadership scope. Bullet-style with sentence fragments is fine.",
          "character_sheet": {
            "class_name": "Pick a fun class that fits the candidate's primary craft, e.g., Backend Wizard, Frontend Bard, DevOps Cleric, Data Druid, Fullstack Ranger, Platform Paladin, ML Sorcerer, Mobile Monk, Security Rogue, SRE Warlock, Embedded Artificer.",
            "class_description": "One short sentence (≤80 chars) on why this class.",
            "level": 1-20 integer, calibrated as: intern/new-grad 1-3, junior 3-6, mid 6-9, senior 9-13, staff/principal 13-17, distinguished/architect 17-20.,
            "attributes": [
              {"name": "Strength",     "abbreviation": "STR", "value": 8-18, "descriptor": "Technical depth — raw problem-solving power and system mastery"},
              {"name": "Dexterity",    "abbreviation": "DEX", "value": 8-18, "descriptor": "Iteration speed, debugging, ability to context-switch and ship fast"},
              {"name": "Constitution", "abbreviation": "CON", "value": 8-18, "descriptor": "Track record of sustained delivery, low-drama, ships consistently"},
              {"name": "Intelligence", "abbreviation": "INT", "value": 8-18, "descriptor": "Learning velocity, abstract thinking, novel-problem analysis"},
              {"name": "Wisdom",       "abbreviation": "WIS", "value": 8-18, "descriptor": "Judgment, system design intuition, knowing when NOT to use a tool"},
              {"name": "Charisma",     "abbreviation": "CHA", "value": 8-18, "descriptor": "Communication, leadership, written/verbal influence"}
            ],
            "specializations": ["2-5 short tags. e.g., 'Distributed Systems', 'React', 'Postgres', 'iOS', 'ML Infra'."],
            "notable_feats": ["2-4 short highlights drawn directly from the resume. Each ≤100 chars. Specific scope/scale beats vague claims."]
          }
        }

        Calibration rules:
        - Default attributes to 10 (median) when the resume doesn't speak to that dimension. Don't inflate.
        - A junior with no leadership shouldn't get CHA above 12. A senior with no system-design exposure shouldn't get WIS above 12.
        - Cap any attribute at 18. Reserve 17-18 for evidence the candidate is exceptional in that dimension.
        - Notable feats must be drawn from the resume content, not generated. If the resume is sparse, return fewer feats rather than padding.

        CANDIDATE: \(candidateName)

        RESUME TEXT:
        \(resumeText)
        """
    }

    // MARK: - Parse

    private static func parse(_ response: String) -> ResumeAnalysis? {
        // Strip code-fence markers if the model added them despite the
        // "no markdown" instruction.
        let stripped = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = stripped.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ResumeAnalysis.self, from: data)
    }
}
