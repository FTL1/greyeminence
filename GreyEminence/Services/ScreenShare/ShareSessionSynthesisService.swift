import Foundation

/// Fuses one share session's detailed frame descriptions with the transcript
/// spoken around it into a narrative recap — the unit the final meeting
/// analysis receives instead of raw per-frame bullets. Runs on the MAIN
/// model: this is synthesis, not perception.
actor ShareSessionSynthesisService {

    /// One analyzed frame's contribution to the synthesis prompt.
    struct FrameObservationLine: Sendable {
        let timestamp: TimeInterval
        let formattedTimestamp: String
        let observation: String
    }

    /// Everything one synthesis call needs — built up front so the service
    /// never touches SwiftData.
    struct SessionInput: Sendable {
        let sessionID: UUID
        let meetingID: UUID?
        let windowTitle: String?
        let startTime: TimeInterval
        let endTime: TimeInterval
        let frameDescriptions: String
        let transcriptExcerpt: String
    }

    struct SessionNarrative: Sendable {
        let sessionID: UUID
        let narrative: String
        let keyMoments: [ShareSessionSummary.KeyMoment]
        let entities: [String]
        let modelIdentifier: String
    }

    enum SynthesisError: LocalizedError {
        case unparseableResponse

        var errorDescription: String? {
            "Session synthesis response had no usable narrative"
        }
    }

    /// Per-frame-line character cap in the prompt.
    static let frameLineCap = 900
    /// Total frame-descriptions budget per synthesis call.
    static let frameBlockCap = 24_000
    /// Transcript excerpt budget.
    static let transcriptCap = 12_000
    /// Transcript window padding around the session bounds.
    static let transcriptPadding: TimeInterval = 30

    private let client: any AIClient

    init(client: any AIClient) {
        self.client = client
    }

    func synthesize(_ input: SessionInput) async throws -> SessionNarrative {
        let userPrompt = AIPromptTemplates.sessionSynthesisPrompt(
            windowTitle: input.windowTitle,
            sessionSpan: Self.span(start: input.startTime, end: input.endTime),
            frameDescriptions: input.frameDescriptions,
            transcriptExcerpt: input.transcriptExcerpt
        )
        let capturedMeetingID = input.meetingID
        LogManager.send("Session synthesis starting (\(Self.span(start: input.startTime, end: input.endTime)))", category: .screen, meetingID: capturedMeetingID)

        let response = try await AIUsageContext.attribute(.sessionSynthesis, meetingID: capturedMeetingID) {
            try await AIRetry.run(label: "sessionSynthesis", meetingID: capturedMeetingID) { [client, userPrompt] in
                try await withTimeout(seconds: 90) {
                    try await client.sendMessage(
                        system: AIPromptTemplates.sessionSynthesisSystemPrompt,
                        userContent: userPrompt,
                        maxTokens: 1500
                    )
                }
            }
        }

        guard let narrative = Self.parse(
            response: response,
            sessionID: input.sessionID,
            modelIdentifier: client.modelIdentifier
        ) else {
            LogManager.send("Session synthesis parse failed — raw: \(response.prefix(400))", category: .screen, level: .warning, meetingID: capturedMeetingID)
            throw SynthesisError.unparseableResponse
        }
        LogManager.send("Session synthesis complete (\(narrative.narrative.count) chars, \(narrative.keyMoments.count) key moment(s))", category: .screen, meetingID: capturedMeetingID)
        return narrative
    }

    // MARK: - Pure helpers (unit-testable)

    /// Assemble a synthesis input from raw parts, applying all the caps:
    /// frame lines truncated to 900 chars each and 24k total (middle lines
    /// dropped first — a session's first and last frames carry its arc),
    /// transcript windowed to [start−30s, end+30s] and capped at 12k chars.
    static func makeInput(
        sessionID: UUID,
        meetingID: UUID?,
        windowTitle: String?,
        startTime: TimeInterval,
        endTime: TimeInterval,
        observations: [FrameObservationLine],
        segments: [SegmentSnapshot]
    ) -> SessionInput {
        var lines = observations
            .sorted { $0.timestamp < $1.timestamp }
            .map { line -> String in
                var text = line.observation
                if text.count > frameLineCap {
                    text = String(text.prefix(frameLineCap)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }
                return "[\(line.formattedTimestamp)] \(text)"
            }
        var totalChars = lines.reduce(0) { $0 + $1.count }
        var droppedAny = false
        while totalChars > frameBlockCap, lines.count > 2 {
            let middle = lines.remove(at: lines.count / 2)
            totalChars -= middle.count
            droppedAny = true
        }
        if droppedAny {
            lines.insert("… (some middle frames omitted for length) …", at: lines.count / 2)
        }

        let windowStart = startTime - transcriptPadding
        let windowEnd = endTime + transcriptPadding
        let spoken = segments
            .filter { $0.startTime >= windowStart && $0.startTime <= windowEnd }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\($0.formattedTimestamp)] \($0.speaker.displayName): \($0.text)" }
        var transcript = spoken.joined(separator: "\n")
        if transcript.count > transcriptCap {
            // Keep both ends — the setup and the reaction matter most.
            let half = transcriptCap / 2
            transcript = String(transcript.prefix(half))
                + "\n… (transcript trimmed) …\n"
                + String(transcript.suffix(half))
        }
        if transcript.isEmpty {
            transcript = "(no speech captured around this session)"
        }

        return SessionInput(
            sessionID: sessionID,
            meetingID: meetingID,
            windowTitle: windowTitle,
            startTime: startTime,
            endTime: endTime,
            frameDescriptions: lines.isEmpty ? "(no analyzed frames)" : lines.joined(separator: "\n"),
            transcriptExcerpt: transcript
        )
    }

    static func parse(response: String, sessionID: UUID, modelIdentifier: String) -> SessionNarrative? {
        guard let json = try? AIResponseDecoder.objectFrom(response),
              let narrative = json["narrative"] as? String,
              !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var keyMoments: [ShareSessionSummary.KeyMoment] = []
        for entry in (json["key_moments"] as? [[String: Any]]) ?? [] {
            guard let label = entry["label"] as? String, !label.isEmpty else { continue }
            let time: TimeInterval?
            if let text = entry["time"] as? String {
                time = parseTimestamp(text)
            } else if let number = entry["time"] as? Double {
                time = number
            } else {
                time = nil
            }
            guard let time else { continue }
            keyMoments.append(ShareSessionSummary.KeyMoment(timestamp: time, label: label))
        }
        keyMoments.sort { $0.timestamp < $1.timestamp }

        return SessionNarrative(
            sessionID: sessionID,
            narrative: narrative.trimmingCharacters(in: .whitespacesAndNewlines),
            keyMoments: keyMoments,
            entities: (json["entities"] as? [String]) ?? [],
            modelIdentifier: modelIdentifier
        )
    }

    /// "m:ss" or "h:mm:ss" → seconds. Nil for anything else.
    static func parseTimestamp(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ":")
            .map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }), !parts.isEmpty else { return nil }
        let values = parts.compactMap { $0 }
        switch values.count {
        case 2: return TimeInterval(values[0] * 60 + values[1])
        case 3: return TimeInterval(values[0] * 3600 + values[1] * 60 + values[2])
        default: return nil
        }
    }

    static func span(start: TimeInterval, end: TimeInterval) -> String {
        "\(format(start))–\(format(end))"
    }

    private static func format(_ elapsed: TimeInterval) -> String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }
}
