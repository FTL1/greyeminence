import Foundation

/// Out-of-band Claude vision analysis of kept screen-share frames. Runs on
/// its own cadence (the VM calls `analyzePendingBatch` every 60s), batches
/// up to `maxFramesPerCall` images per request, and enforces a per-meeting
/// budget. Failures degrade to OCR-only frames — never to a broken recording.
actor ScreenFrameAnalysisService {

    /// What the analysis pass needs from a kept frame — built on the
    /// MainActor from `KeptFrame` + its stamped elapsed timestamp.
    struct FrameSnapshot: Sendable {
        let frameID: UUID
        let sessionID: UUID
        let timestamp: TimeInterval
        let formattedTimestamp: String
        let jpegData: Data
        let ocrExcerpt: String?
        let isVisualOnlyChange: Bool
    }

    struct FrameObservation: Sendable {
        let frameID: UUID
        let timestamp: TimeInterval
        let formattedTimestamp: String
        let sessionID: UUID
        let observation: String
        let contentType: String
        let keyEntities: [String]
        let notableText: String?
    }

    /// Result of one batch pass, applied to SwiftData rows by the caller.
    struct BatchResult: Sendable {
        var observations: [FrameObservation] = []
        /// Frames the model was asked about but the call failed terminally.
        var failedIDs: [UUID] = []
        /// Frames dropped without analysis (batch overflow or budget).
        var skippedIDs: [UUID] = []
    }

    /// OCR characters included per frame in the prompt manifest.
    static let manifestOCRLimit = 500

    private let client: any AIClient
    private let meetingID: UUID?
    private let maxFramesPerCall: Int
    private let maxAnalyzedPerMeeting: Int

    private var pending: [FrameSnapshot] = []
    private(set) var analyzedCount = 0
    private var budgetExhausted = false

    init(
        client: any AIClient,
        meetingID: UUID?,
        maxFramesPerCall: Int = 4,
        maxAnalyzedPerMeeting: Int
    ) {
        self.client = client
        self.meetingID = meetingID
        self.maxFramesPerCall = maxFramesPerCall
        self.maxAnalyzedPerMeeting = maxAnalyzedPerMeeting
    }

    var analysisModelIdentifier: String { client.modelIdentifier }

    /// Queue frames for the next batch. Returns IDs refused because the
    /// per-meeting budget is exhausted (callers mark those rows `skipped`).
    func enqueue(_ frames: [FrameSnapshot]) -> [UUID] {
        guard !budgetExhausted else {
            LogManager.send("Frame analysis enqueue refused (\(frames.count) frame(s)): budget exhausted", category: .screen, meetingID: meetingID)
            return frames.map(\.frameID)
        }
        pending.append(contentsOf: frames)
        return []
    }

    /// Analyze one batch if anything is pending. Drains the entire pending
    /// list each call: up to `maxFramesPerCall` frames are analyzed, the rest
    /// are skipped (kept with OCR only) — bounded cost AND bounded staleness,
    /// rather than an ever-growing backlog.
    func analyzePendingBatch(recentTopics: [String]) async -> BatchResult {
        var result = BatchResult()
        guard !pending.isEmpty else { return result }

        let drained = pending
        pending = []

        var batch = Self.selectBatch(
            from: drained,
            limit: min(maxFramesPerCall, max(0, maxAnalyzedPerMeeting - analyzedCount))
        )
        let batchIDs = Set(batch.map(\.frameID))
        result.skippedIDs = drained.map(\.frameID).filter { !batchIDs.contains($0) }
        guard !batch.isEmpty else {
            budgetExhausted = true
            return result
        }
        batch.sort { $0.timestamp < $1.timestamp }

        let manifest = batch.enumerated().map { index, frame in
            let ocr = frame.ocrExcerpt.map { String($0.prefix(Self.manifestOCRLimit)) } ?? "(no text recognized)"
            return "Image \(index) — captured at [\(frame.formattedTimestamp)]:\n\(ocr)"
        }.joined(separator: "\n\n")

        let userPrompt = AIPromptTemplates.screenAnalysisPrompt(
            frameCount: batch.count,
            frameManifest: manifest,
            recentTopics: recentTopics
        )
        let images = batch.map { AIImageContent(jpegData: $0.jpegData) }
        let systemPrompt = AIPromptTemplates.screenSystemPrompt
        let capturedMeetingID = meetingID

        LogManager.send("Screen-frame analysis batch starting (\(batch.count) frames, \(result.skippedIDs.count) skipped)", category: .screen, meetingID: meetingID)

        let response: String
        do {
            response = try await AIRetry.run(label: "screenFrames", meetingID: capturedMeetingID) { [client] in
                try await withTimeout(seconds: 90) {
                    try await client.sendMessage(
                        system: systemPrompt,
                        userContent: userPrompt,
                        images: images,
                        maxTokens: 2048
                    )
                }
            }
        } catch {
            result.failedIDs = batch.map(\.frameID)
            LogManager.send("Screen-frame analysis failed (frames keep OCR only): \(error.localizedDescription)", category: .screen, level: .warning, meetingID: meetingID)
            return result
        }

        result.observations = Self.parse(response: response, batch: batch, meetingID: meetingID)
        let unparsed = batchIDs.subtracting(result.observations.map(\.frameID))
        result.failedIDs.append(contentsOf: unparsed)
        LogManager.send(
            "Screen-frame analysis batch complete: \(result.observations.count) observation(s), \(result.failedIDs.count) failed, \(result.skippedIDs.count) skipped (\(client.modelIdentifier))",
            category: .screen,
            meetingID: meetingID
        )

        analyzedCount += result.observations.count
        if analyzedCount >= maxAnalyzedPerMeeting {
            budgetExhausted = true
            LogManager.send("Screen-frame analysis budget reached (\(analyzedCount)) — later frames keep OCR only", category: .screen, level: .warning, meetingID: meetingID)
        }
        return result
    }

    // MARK: - Pure helpers (unit-testable)

    /// Pick the frames worth spending vision tokens on: real content changes
    /// first, then even spacing across the timeline for whatever room is left.
    static func selectBatch(from frames: [FrameSnapshot], limit: Int) -> [FrameSnapshot] {
        guard limit > 0 else { return [] }
        guard frames.count > limit else { return frames }

        let preferred = frames.filter { !$0.isVisualOnlyChange }
        let pool = preferred.count >= limit ? preferred : frames
        guard pool.count > limit else { return pool }

        // Evenly spaced picks across the (chronologically ordered) pool.
        let sorted = pool.sorted { $0.timestamp < $1.timestamp }
        let step = Double(sorted.count - 1) / Double(limit - 1 == 0 ? 1 : limit - 1)
        var picked: [FrameSnapshot] = []
        var seen = Set<UUID>()
        for i in 0..<limit {
            let index = Int((Double(i) * step).rounded())
            let frame = sorted[min(index, sorted.count - 1)]
            if seen.insert(frame.frameID).inserted {
                picked.append(frame)
            }
        }
        return picked
    }

    static func parse(response: String, batch: [FrameSnapshot], meetingID: UUID?) -> [FrameObservation] {
        let json: [String: Any]
        do {
            json = try AIResponseDecoder.objectFrom(response)
        } catch {
            LogManager.send("Screen-frame analysis parse failed: \(error.localizedDescription) — raw: \(response.prefix(500))", category: .screen, level: .warning, meetingID: meetingID)
            return []
        }
        guard let frames = json["frames"] as? [[String: Any]] else { return [] }

        var observations: [FrameObservation] = []
        for entry in frames {
            guard let index = entry["index"] as? Int,
                  batch.indices.contains(index),
                  let observation = entry["observation"] as? String,
                  !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let frame = batch[index]
            let notable = entry["notable_text"] as? String
            observations.append(FrameObservation(
                frameID: frame.frameID,
                timestamp: frame.timestamp,
                formattedTimestamp: frame.formattedTimestamp,
                sessionID: frame.sessionID,
                observation: observation,
                contentType: (entry["content_type"] as? String) ?? "other",
                keyEntities: (entry["key_entities"] as? [String]) ?? [],
                notableText: (notable?.isEmpty ?? true) ? nil : notable
            ))
        }
        return observations
    }
}
