import Foundation

/// Decides which captured screenshots evidence which section of the summary.
///
/// One text-only call — the frames' observations already exist, so no images
/// are uploaded and the pass costs a fraction of a frame-analysis batch. The
/// result is cached per insight, so switching templates or re-exporting the
/// same meeting is free.
actor ReportComposerService {

    /// A screenshot offered to the model, reduced to what it needs to judge
    /// relevance.
    struct FrameCandidate: Sendable {
        let id: UUID
        let formattedTimestamp: String
        let observation: String
        let contentType: String?
        let entities: [String]
    }

    struct SectionOutline: Sendable {
        let index: Int
        let title: String
        /// Point labels — enough to judge relevance without paying for the
        /// full detail text of every bullet.
        let pointLabels: [String]
    }

    enum ComposerError: LocalizedError {
        case unparseableResponse

        var errorDescription: String? {
            "The figure-anchoring response could not be read"
        }
    }

    /// Beyond this many candidates the prompt stops being worth its tokens and
    /// the model's judgement degrades. Frames are pre-ranked by the caller.
    static let maxCandidates = 40
    /// Observations run 100–250 words and the specifics live throughout —
    /// document titles, field names, values. Cutting at 300 characters threw
    /// away exactly what a useful caption is made of and left the model
    /// describing the application window instead of its contents.
    static let observationCap = 700

    private let client: any AIClient

    init(client: any AIClient) {
        self.client = client
    }

    func anchors(
        sections: [SectionOutline],
        frames: [FrameCandidate],
        insightID: UUID,
        meetingID: UUID?
    ) async throws -> ReportAnchorPlan {
        // Nothing to place, or nowhere to place it — never spend a call.
        guard !sections.isEmpty, !frames.isEmpty else {
            return ReportAnchorPlan(
                version: ReportAnchorPlan.currentVersion,
                insightID: insightID,
                anchors: [],
                createdAt: .now,
                modelIdentifier: client.modelIdentifier
            )
        }

        let candidates = Array(frames.prefix(Self.maxCandidates))
        let prompt = AIPromptTemplates.figureAnchorPrompt(
            sectionOutline: Self.renderSections(sections),
            frameCatalogue: Self.renderFrames(candidates)
        )

        LogManager.send(
            "Figure anchoring starting (\(sections.count) sections, \(candidates.count) candidate frames)",
            category: .general,
            meetingID: meetingID
        )

        let response = try await AIUsageContext.attribute(.reportFigureAnchors, meetingID: meetingID) {
            try await AIRetry.run(label: "reportFigureAnchors", meetingID: meetingID) { [client, prompt] in
                try await withTimeout(seconds: 60) {
                    try await client.sendMessage(
                        system: AIPromptTemplates.reportSystemPrompt,
                        userContent: prompt,
                        maxTokens: 1500
                    )
                }
            }
        }

        guard let anchors = Self.parse(response: response, sections: sections, frames: candidates) else {
            // Log the payload before giving up — the same discipline the
            // Bedrock model-drift bug forced on every other decoder here.
            LogManager.send(
                "Figure anchoring parse failed — raw: \(response.prefix(400))",
                category: .general,
                level: .warning,
                meetingID: meetingID
            )
            throw ComposerError.unparseableResponse
        }

        LogManager.send(
            "Figure anchoring complete (\(anchors.count) of \(candidates.count) frame(s) anchored)",
            category: .general,
            meetingID: meetingID
        )
        return ReportAnchorPlan(
            version: ReportAnchorPlan.currentVersion,
            insightID: insightID,
            anchors: anchors,
            createdAt: .now,
            modelIdentifier: client.modelIdentifier
        )
    }

    // MARK: - Pure helpers (unit-tested)

    static func renderSections(_ sections: [SectionOutline]) -> String {
        sections.map { section in
            let points = section.pointLabels
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(8)
            let detail = points.isEmpty ? "" : "\n    " + points.joined(separator: "\n    ")
            return "S\(section.index): \(section.title)\(detail)"
        }
        .joined(separator: "\n")
    }

    /// Short indices rather than UUIDs: a 36-character identifier repeated
    /// forty times is pure token cost, and models transcribe them wrong.
    static func renderFrames(_ frames: [FrameCandidate]) -> String {
        frames.enumerated().map { index, frame in
            var observation = frame.observation.trimmingCharacters(in: .whitespacesAndNewlines)
            if observation.count > observationCap {
                observation = String(observation.prefix(observationCap)) + "…"
            }
            var parts = ["F\(index + 1)", frame.formattedTimestamp]
            if let type = frame.contentType { parts.append(type) }
            parts.append(observation.isEmpty ? "(no description)" : observation)
            if !frame.entities.isEmpty {
                parts.append("[" + frame.entities.prefix(6).joined(separator: ", ") + "]")
            }
            return parts.joined(separator: " | ")
        }
        .joined(separator: "\n")
    }

    /// Decode tolerantly: accept the JSON wherever it sits in the response,
    /// ignore anchors naming identifiers that do not exist, and never let one
    /// bad entry discard the good ones.
    static func parse(
        response: String,
        sections: [SectionOutline],
        frames: [FrameCandidate]
    ) -> [ReportAnchorPlan.Anchor]? {
        guard let json = extractJSONObject(from: response),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawPlan.self, from: data) else {
            return nil
        }

        let validSections = Set(sections.map(\.index))
        return decoded.entries.compactMap { raw -> ReportAnchorPlan.Anchor? in
            // The frame must resolve — an entry naming no real screenshot is
            // meaningless. The section is allowed to be absent: most
            // screenshots evidence nothing in particular and are captioned
            // without being anchored.
            guard let frameOrdinal = Self.index(from: raw.frame, prefix: "F"),
                  frameOrdinal >= 1, frameOrdinal <= frames.count else {
                return nil
            }
            var sectionIndex: Int?
            if let token = raw.section, let parsed = Self.index(from: token, prefix: "S"),
               validSections.contains(parsed) {
                sectionIndex = parsed
            }
            return ReportAnchorPlan.Anchor(
                sectionIndex: sectionIndex,
                frameID: frames[frameOrdinal - 1].id,
                caption: raw.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Accepts `figures` (current) or `anchors` (what the first version of
    /// this prompt asked for) — a user who has overridden the prompt in
    /// developer settings keeps working across the rename.
    private struct RawPlan: Decodable {
        struct RawEntry: Decodable {
            /// Absent, JSON null, or a string like "none" all mean unanchored.
            let section: String?
            let frame: String
            let caption: String
        }
        let entries: [RawEntry]

        private enum CodingKeys: String, CodingKey {
            case figures, anchors
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let figures = try container.decodeIfPresent([RawEntry].self, forKey: .figures) {
                entries = figures
            } else {
                entries = try container.decode([RawEntry].self, forKey: .anchors)
            }
        }
    }

    /// "S3" → 3. Tolerates a bare number and stray whitespace, because both
    /// turn up in practice.
    static func index(from token: String, prefix: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
        return Int(digits)
    }

    /// Models wrap JSON in prose or a markdown fence however firmly they are
    /// told not to. Take the outermost balanced object.
    static func extractJSONObject(from response: String) -> String? {
        guard let start = response.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < response.endIndex {
            let character = response[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(response[start...index])
                    }
                }
            }
            index = response.index(after: index)
        }
        return nil
    }
}
