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
        /// Which model produced `observations` — stamped on the rows as
        /// provenance. The frame client's model, NOT the main model.
        var modelIdentifier: String?
    }

    /// OCR characters included per frame in the prompt manifest.
    static let manifestOCRLimit = 500
    /// Characters of the last applied observation carried into the next
    /// batch's prompt as change-vs-previous context.
    static let previousObservationLimit = 300
    /// Visual-only (video-churn) frames analyzed at most this often per session.
    static let visualOnlyMinimumGap: TimeInterval = 60

    private let client: any AIClient
    private let meetingID: UUID?
    private let maxFramesPerCall: Int
    private let maxAnalyzedPerMeeting: Int
    private let analysisPixelBudget: Int

    private var pending: [FrameSnapshot] = []
    private(set) var analyzedCount = 0
    private var budgetExhausted = false
    /// Last visual-only frame allowed through the throttle, per session.
    private var visualOnlyLastAllowedAt: [UUID: TimeInterval] = [:]
    /// First ~300 chars of the chronologically last observation applied —
    /// gives the next batch's first frame change-vs-previous context.
    private var previousObservationExcerpt: String?

    init(
        client: any AIClient,
        meetingID: UUID?,
        maxFramesPerCall: Int = 4,
        maxAnalyzedPerMeeting: Int,
        analysisPixelBudget: Int = ScreenShareSettings.analysisPixelBudget
    ) {
        self.client = client
        self.meetingID = meetingID
        self.maxFramesPerCall = maxFramesPerCall
        self.maxAnalyzedPerMeeting = maxAnalyzedPerMeeting
        self.analysisPixelBudget = analysisPixelBudget
    }

    var analysisModelIdentifier: String { client.modelIdentifier }

    /// Queue frames for the next batch. Returns IDs refused (budget exhausted
    /// or a blank white/black capture). Callers mark those rows `skipped`.
    func enqueue(_ frames: [FrameSnapshot]) -> [UUID] {
        guard !budgetExhausted else {
            LogManager.send("Frame analysis enqueue refused (\(frames.count) frame(s)): budget exhausted", category: .screen, meetingID: meetingID)
            return frames.map(\.frameID)
        }
        var kept: [FrameSnapshot] = []
        var blank: [UUID] = []
        for frame in frames {
            if ScreenFrameTriage.isBlankJPEG(frame.jpegData) {
                blank.append(frame.frameID)
            } else {
                kept.append(frame)
            }
        }
        if !blank.isEmpty {
            LogManager.send(
                "Skipped \(blank.count) blank screen frame(s) — not sent for vision analysis",
                category: .screen,
                meetingID: meetingID
            )
        }
        pending.append(contentsOf: kept)
        return blank
    }

    /// Analyze one batch if anything is pending. Drains the entire pending
    /// list each call: up to `maxFramesPerCall` frames are analyzed, the rest
    /// are skipped (kept with OCR only) — bounded cost AND bounded staleness,
    /// rather than an ever-growing backlog.
    func analyzePendingBatch(recentTopics: [String]) async -> BatchResult {
        var result = BatchResult()
        result.modelIdentifier = client.modelIdentifier
        guard !pending.isEmpty else { return result }

        let drained = pending
        pending = []

        // Video churn first: at most one visual-only frame per minute per
        // session gets to compete for the batch; the rest go straight to
        // skipped.
        let throttled = Self.throttleVisualOnly(
            drained,
            lastAnalyzedAt: visualOnlyLastAllowedAt,
            minimumGap: Self.visualOnlyMinimumGap
        )
        visualOnlyLastAllowedAt = throttled.lastAnalyzedAt
        result.skippedIDs = throttled.droppedIDs

        var batch = Self.selectBatch(
            from: throttled.kept,
            limit: min(maxFramesPerCall, max(0, maxAnalyzedPerMeeting - analyzedCount))
        )
        let batchIDs = Set(batch.map(\.frameID))
        result.skippedIDs.append(contentsOf: throttled.kept.map(\.frameID).filter { !batchIDs.contains($0) })
        guard !batch.isEmpty else {
            if !throttled.kept.isEmpty {
                budgetExhausted = true
            }
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
            recentTopics: recentTopics,
            previousObservation: previousObservationExcerpt
        )
        let pixelBudget = analysisPixelBudget
        let payloads = batch.map { ScreenFrameTriage.downscaledJPEG($0.jpegData, targetPixelCount: pixelBudget) }
        let images = payloads.map { AIImageContent(jpegData: $0) }
        let systemPrompt = AIPromptTemplates.screenSystemPrompt
        let capturedMeetingID = meetingID

        let originalKB = batch.reduce(0) { $0 + $1.jpegData.count } / 1024
        let payloadKB = payloads.reduce(0) { $0 + $1.count } / 1024
        LogManager.send("Screen-frame analysis batch starting (\(batch.count) frames, \(result.skippedIDs.count) skipped, payload \(payloadKB) KB from \(originalKB) KB)", category: .screen, meetingID: meetingID)

        let response: String
        do {
            response = try await AIUsageContext.attribute(.frameAnalysis, meetingID: capturedMeetingID) {
                try await AIRetry.run(label: "screenFrames", meetingID: capturedMeetingID) { [client] in
                    try await withTimeout(seconds: 90) {
                        try await client.sendMessage(
                            system: systemPrompt,
                            userContent: userPrompt,
                            images: images,
                            maxTokens: 6000
                        )
                    }
                }
            }
        } catch {
            result.failedIDs = batch.map(\.frameID)
            LogManager.send("Screen-frame analysis failed (frames keep OCR only): \(error.localizedDescription)", category: .screen, level: .warning, meetingID: meetingID)
            return result
        }

        result.observations = Self.parse(response: response, batch: batch, meetingID: meetingID)
        if let latest = result.observations.max(by: { $0.timestamp < $1.timestamp }) {
            previousObservationExcerpt = String(latest.observation.prefix(Self.previousObservationLimit))
        }
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

    /// Rate-limit video churn: visual-only frames (hash moved, words didn't)
    /// pass at most once per `minimumGap` seconds per session; the rest are
    /// dropped as skipped. Real content changes always pass. Returns the
    /// updated per-session map so the throttle carries across batches.
    static func throttleVisualOnly(
        _ frames: [FrameSnapshot],
        lastAnalyzedAt: [UUID: TimeInterval],
        minimumGap: TimeInterval = 60
    ) -> (kept: [FrameSnapshot], droppedIDs: [UUID], lastAnalyzedAt: [UUID: TimeInterval]) {
        var last = lastAnalyzedAt
        var kept: [FrameSnapshot] = []
        var droppedIDs: [UUID] = []
        for frame in frames.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard frame.isVisualOnlyChange else {
                kept.append(frame)
                continue
            }
            if let previous = last[frame.sessionID], frame.timestamp - previous < minimumGap {
                droppedIDs.append(frame.frameID)
            } else {
                last[frame.sessionID] = frame.timestamp
                kept.append(frame)
            }
        }
        return (kept, droppedIDs, last)
    }

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
