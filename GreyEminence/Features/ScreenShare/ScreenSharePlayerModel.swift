import AppKit
import Foundation
import SwiftData

/// Drives the post-meeting time-lapse player. Snapshots `ScreenShareFrame`
/// rows into value types once (the play loop and Canvas never touch live
/// @Models), owns the playhead, and exposes seek/step/search/frame actions.
@Observable
@MainActor
final class ScreenSharePlayerModel {

    struct FrameItem: Identifiable, Sendable, Equatable {
        let id: UUID
        let sessionID: UUID
        let timestamp: TimeInterval
        let formattedTimestamp: String
        let imageURL: URL
        let observation: String?
        let ocrText: String?
        let analysisState: FrameAnalysisState
        let contentType: String?
        let isVisualOnlyChange: Bool
    }

    enum Dwell: Double, CaseIterable, Identifiable {
        case normal = 0.8
        case fast = 0.4
        case fastest = 0.2

        var id: Double { rawValue }
        var label: String {
            switch self {
            case .normal: "1×"
            case .fast: "2×"
            case .fastest: "4×"
            }
        }
    }

    /// Snapshot of one session's synthesized recap for the player UI.
    struct RecapItem: Sendable, Equatable {
        let sessionID: UUID
        let narrative: String
        let keyMoments: [ShareSessionSummary.KeyMoment]
    }

    private(set) var frames: [FrameItem] = []
    private(set) var sessions: [ShareSession] = []
    private(set) var recapsBySession: [UUID: RecapItem] = [:]
    private(set) var meetingDuration: TimeInterval = 0
    private let meetingID: UUID

    var currentIndex: Int = 0 {
        didSet {
            guard currentIndex != oldValue, frames.indices.contains(currentIndex) else { return }
            onPlayheadChanged?(frames[currentIndex].timestamp)
        }
    }
    private(set) var isPlaying = false
    var dwell: Dwell = .normal

    /// Fired whenever the playhead lands on a new frame — the section maps
    /// it to the nearest transcript segment (throttled there).
    var onPlayheadChanged: ((TimeInterval) -> Void)?

    // OCR search
    var searchText: String = "" {
        didSet { updateMatches() }
    }
    private(set) var matchIndices: [Int] = []
    private(set) var analyzingFrameIDs: Set<UUID> = []

    private var playTask: Task<Void, Never>?

    init(meeting: Meeting) {
        self.meetingID = meeting.id
        refresh(from: meeting)
    }

    /// Re-snapshot from the model — used at init and when the row count
    /// changes (late observations, deletions).
    func refresh(from meeting: Meeting) {
        let storage = StorageManager.shared
        frames = meeting.screenFrames
            .sorted { ($0.timestamp, $0.sequence) < ($1.timestamp, $1.sequence) }
            .map { row in
                FrameItem(
                    id: row.id,
                    sessionID: row.sessionID,
                    timestamp: row.timestamp,
                    formattedTimestamp: row.formattedTimestamp,
                    imageURL: storage.frameURL(for: meeting.id, relativePath: row.imagePath),
                    observation: row.observation,
                    ocrText: row.ocrText,
                    analysisState: row.analysisState,
                    contentType: row.contentTypeRaw,
                    isVisualOnlyChange: row.isVisualOnlyChange
                )
            }
        sessions = ShareSession.sessions(from: meeting.screenFrames)
        recapsBySession = Dictionary(uniqueKeysWithValues: meeting.sessionSummaries.map { summary in
            (summary.sessionID, RecapItem(
                sessionID: summary.sessionID,
                narrative: summary.narrative,
                keyMoments: summary.keyMoments
            ))
        })
        meetingDuration = max(meeting.duration, frames.last?.timestamp ?? 0)
        currentIndex = min(currentIndex, max(0, frames.count - 1))
        updateMatches()
    }

    var currentFrame: FrameItem? {
        frames.indices.contains(currentIndex) ? frames[currentIndex] : nil
    }

    var playhead: TimeInterval { currentFrame?.timestamp ?? 0 }

    // MARK: - Playback

    /// Single sleep-loop task; inter-session gaps pass instantly because the
    /// dwell is per *frame*, not per second of meeting time.
    func play() {
        guard !isPlaying, !frames.isEmpty else { return }
        if currentIndex >= frames.count - 1 {
            currentIndex = 0
        }
        isPlaying = true
        playTask = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.dwell.rawValue))
                guard self.isPlaying, !Task.isCancelled else { return }
                if self.currentIndex < self.frames.count - 1 {
                    self.currentIndex += 1
                } else {
                    self.pause()
                }
            }
        }
    }

    func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Nearest frame at-or-before `time` (or the first frame when `time`
    /// precedes the first capture).
    func seek(to time: TimeInterval) {
        guard !frames.isEmpty else { return }
        let index = frames.lastIndex(where: { $0.timestamp <= time }) ?? 0
        currentIndex = index
    }

    func step(_ delta: Int) {
        guard !frames.isEmpty else { return }
        pause()
        currentIndex = min(max(currentIndex + delta, 0), frames.count - 1)
    }

    func select(frameID: UUID) {
        guard let index = frames.firstIndex(where: { $0.id == frameID }) else { return }
        pause()
        currentIndex = index
    }

    // MARK: - OCR search

    private func updateMatches() {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else {
            matchIndices = []
            return
        }
        matchIndices = frames.indices.filter { index in
            frames[index].ocrText?.localizedCaseInsensitiveContains(needle) == true
                || frames[index].observation?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    func nextMatch() {
        guard !matchIndices.isEmpty else { return }
        pause()
        currentIndex = matchIndices.first(where: { $0 > currentIndex }) ?? matchIndices[0]
    }

    func previousMatch() {
        guard !matchIndices.isEmpty else { return }
        pause()
        currentIndex = matchIndices.last(where: { $0 < currentIndex }) ?? matchIndices[matchIndices.count - 1]
    }

    // MARK: - Frame actions

    func copyImage(_ frame: FrameItem) {
        guard let image = NSImage(contentsOf: frame.imageURL) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func copyOCRText(_ frame: FrameItem) {
        guard let text = frame.ocrText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openImage(_ frame: FrameItem) {
        NSWorkspace.shared.open(frame.imageURL)
    }

    /// Delete a frame's row, image file, and embedding record, then
    /// re-snapshot.
    func deleteFrame(_ frame: FrameItem, meeting: Meeting, context: ModelContext) {
        deleteFrames(ids: [frame.id], meeting: meeting, context: context)
    }

    /// Privacy hatch: delete an entire share session ("I shared the wrong
    /// window") — frames, narrative summary, and their embeddings.
    func deleteSession(_ sessionID: UUID, meeting: Meeting, context: ModelContext) {
        let ids = Set(frames.filter { $0.sessionID == sessionID }.map(\.id))
        deleteFrames(ids: ids, meeting: meeting, context: context)
        if let summary = meeting.sessionSummaries.first(where: { $0.sessionID == sessionID }) {
            EmbeddingStore.shared?.deleteRecord(id: "sessionSummary:\(sessionID.uuidString)")
            meeting.sessionSummaries.removeAll { $0.sessionID == sessionID }
            context.delete(summary)
            PersistenceGate.save(context, site: "ScreenSharePlayer.deleteSessionSummary", meetingID: meeting.id)
            refresh(from: meeting)
        }
    }

    private func deleteFrames(ids: Set<UUID>, meeting: Meeting, context: ModelContext) {
        let rows = meeting.screenFrames.filter { ids.contains($0.id) }
        for row in rows {
            let url = StorageManager.shared.frameURL(for: meeting.id, relativePath: row.imagePath)
            try? FileManager.default.removeItem(at: url)
            EmbeddingStore.shared?.deleteRecord(id: "frame:\(row.id.uuidString)")
            context.delete(row)
        }
        meeting.screenFrames.removeAll { ids.contains($0.id) }
        PersistenceGate.save(context, site: "ScreenSharePlayer.deleteFrames", meetingID: meeting.id)
        refresh(from: meeting)
        LogManager.shared.log("Deleted \(rows.count) screen frame(s)", category: .screen, meetingID: meeting.id)
    }

    /// Build a vision-capable client, logging the REAL failure reason —
    /// "no API key" and "AWS SSO token expired" are different problems and
    /// the log must say which one it is.
    private static func makeVisionClient(meetingID: UUID, context: String) async -> (any AIClient)? {
        do {
            guard let client = try await AIClientFactory.makeFrameAnalysisClient() else {
                LogManager.shared.log("\(context) skipped: no API key configured", category: .screen, level: .warning, meetingID: meetingID)
                return nil
            }
            guard client.supportsImages else {
                LogManager.shared.log("\(context) skipped: \(client.modelIdentifier) has no image support", category: .screen, level: .warning, meetingID: meetingID)
                return nil
            }
            return client
        } catch {
            LogManager.shared.log("\(context) skipped: AI client failed — \(error.localizedDescription)", category: .screen, level: .warning, meetingID: meetingID)
            return nil
        }
    }

    // MARK: - Bulk analysis backfill

    private(set) var isBulkAnalyzing = false
    private(set) var bulkProgress: (done: Int, total: Int)?

    var hasUnanalyzedFrames: Bool {
        frames.contains { $0.observation == nil }
    }

    /// Backfill Claude observations for every frame that never got one —
    /// frames captured while the AI was unconfigured, budget-skipped, or
    /// failed. Runs in batches of 4, bounded by the per-meeting budget.
    func analyzeAllFrames(meeting: Meeting, context: ModelContext) async {
        guard !isBulkAnalyzing else { return }
        let targets = frames.filter { $0.observation == nil }
        guard !targets.isEmpty else { return }
        guard let client = await Self.makeVisionClient(meetingID: meeting.id, context: "Frame backfill") else { return }
        LogManager.shared.log("Frame backfill starting (\(targets.count) unanalyzed frame(s))", category: .screen, meetingID: meeting.id)

        isBulkAnalyzing = true
        defer {
            isBulkAnalyzing = false
            bulkProgress = nil
        }

        let budget = min(targets.count, ScreenShareSettings.maxAnalyzedFrames)
        let service = ScreenFrameAnalysisService(
            client: client,
            meetingID: meeting.id,
            maxAnalyzedPerMeeting: budget
        )
        let topics = meeting.latestInsight?.topics ?? []
        var done = 0
        bulkProgress = (0, budget)

        var index = 0
        while index < budget {
            let chunk = Array(targets[index..<min(index + 4, budget)])
            index += chunk.count

            let snapshots: [ScreenFrameAnalysisService.FrameSnapshot] = chunk.compactMap { item in
                guard let data = try? Data(contentsOf: item.imageURL) else { return nil }
                return ScreenFrameAnalysisService.FrameSnapshot(
                    frameID: item.id,
                    sessionID: item.sessionID,
                    timestamp: item.timestamp,
                    formattedTimestamp: item.formattedTimestamp,
                    jpegData: data,
                    ocrExcerpt: item.ocrText,
                    isVisualOnlyChange: false
                )
            }
            guard !snapshots.isEmpty else { continue }

            analyzingFrameIDs.formUnion(snapshots.map(\.frameID))
            _ = await service.enqueue(snapshots)
            let result = await service.analyzePendingBatch(recentTopics: topics)
            analyzingFrameIDs.subtract(snapshots.map(\.frameID))

            apply(result, to: meeting)
            done += result.observations.count
            bulkProgress = (done, budget)
        }

        PersistenceGate.save(context, site: "ScreenSharePlayer.analyzeAllFrames", meetingID: meeting.id)
        refresh(from: meeting)
        LogManager.shared.log("Backfilled \(done) frame observation(s)", category: .screen, meetingID: meeting.id)

        // Fresh observations usually unlock session recaps — chain the
        // narrative backfill so one click covers both.
        await generateRecaps(meeting: meeting, context: context)
    }

    /// Force a full redo of screen-share intelligence: wipe every frame's
    /// observation and every session recap, then re-run vision analysis
    /// (which chains recap synthesis) and re-index embeddings. The "my
    /// frame descriptions predate a prompt fix" recovery, akin to
    /// re-transcribing with large-v3.
    func reanalyzeAllShares(meeting: Meeting, context: ModelContext) async {
        guard !isBulkAnalyzing, !isGeneratingRecaps, !meeting.screenFrames.isEmpty else { return }
        LogManager.shared.log("Screen-share redo: wiping \(meeting.screenFrames.count) observation(s) and \(meeting.sessionSummaries.count) recap(s)", category: .screen, meetingID: meeting.id)

        for row in meeting.screenFrames {
            row.observation = nil
            row.contentTypeRaw = nil
            row.keyEntities = []
            row.analysisModelIdentifier = nil
            row.analysisState = .ocrOnly
        }
        for summary in meeting.sessionSummaries {
            EmbeddingStore.shared?.deleteRecord(id: "sessionSummary:\(summary.sessionID.uuidString)")
            context.delete(summary)
        }
        meeting.sessionSummaries.removeAll()
        PersistenceGate.save(context, site: "ScreenSharePlayer.reanalyzeShares/wipe", meetingID: meeting.id)
        refresh(from: meeting)

        // Fresh vision pass over now-unanalyzed frames; chains recap
        // synthesis when it finishes.
        await analyzeAllFrames(meeting: meeting, context: context)

        // Frame + recap embeddings are stale — re-index the meeting so Ask
        // reflects the new descriptions (upserts by id, so this is safe to
        // run over everything).
        if let store = EmbeddingStore.shared {
            let providerRaw = UserDefaults.standard.string(forKey: "embeddingProvider") ?? EmbeddingProvider.nlEmbedding.rawValue
            let provider = EmbeddingProvider(rawValue: providerRaw) ?? .nlEmbedding
            await EmbeddingIndexer(store: store, service: provider.makeService()).indexMeeting(meeting)
        }
        LogManager.shared.log("Screen-share redo complete", category: .screen, meetingID: meeting.id)
    }

    // MARK: - Session recap backfill

    private(set) var isGeneratingRecaps = false

    /// True when at least one session has analyzed frames but no narrative —
    /// the "Generate Recaps" button's visibility condition.
    var hasSessionsWithoutRecaps: Bool {
        sessions.contains { session in
            recapsBySession[session.id] == nil
                && frames.contains { $0.sessionID == session.id && !($0.observation ?? "").isEmpty }
        }
    }

    /// Synthesize narratives for every session that has observations but no
    /// summary. Runs on the MAIN model — recaps are synthesis, not frame
    /// perception.
    func generateRecaps(meeting: Meeting, context: ModelContext) async {
        guard !isGeneratingRecaps else { return }
        let existing = Set(meeting.sessionSummaries.map(\.sessionID))
        let targets = ShareSession.sessions(from: meeting.screenFrames).filter { session in
            !existing.contains(session.id)
                && meeting.screenFrames.contains { $0.sessionID == session.id && !($0.observation ?? "").isEmpty }
        }
        guard !targets.isEmpty else { return }
        guard let client = try? await AIClientFactory.makeClient() else {
            LogManager.shared.log("Recap backfill skipped: AI client unavailable", category: .screen, level: .warning, meetingID: meeting.id)
            return
        }
        isGeneratingRecaps = true
        defer { isGeneratingRecaps = false }
        LogManager.shared.log("Recap backfill starting (\(targets.count) session(s))", category: .screen, meetingID: meeting.id)

        let service = ShareSessionSynthesisService(client: client)
        let segments = meeting.segments
            .sorted { $0.startTime < $1.startTime }
            .map { SegmentSnapshot(speaker: $0.speaker, text: $0.text, formattedTimestamp: $0.formattedTimestamp, isFinal: $0.isFinal, startTime: $0.startTime) }

        var generated = 0
        for session in targets {
            let sessionFrames = meeting.screenFrames.filter { $0.sessionID == session.id }
            let observations: [ShareSessionSynthesisService.FrameObservationLine] = sessionFrames.compactMap { row in
                guard let text = row.observation, !text.isEmpty else { return nil }
                return ShareSessionSynthesisService.FrameObservationLine(
                    timestamp: row.timestamp,
                    formattedTimestamp: row.formattedTimestamp,
                    observation: text
                )
            }
            guard !observations.isEmpty else { continue }
            let input = ShareSessionSynthesisService.makeInput(
                sessionID: session.id,
                meetingID: meeting.id,
                windowTitle: session.windowTitle,
                startTime: session.startTime,
                endTime: session.endTime,
                observations: observations,
                segments: segments
            )
            guard let narrative = try? await service.synthesize(input) else { continue }
            let summary = ShareSessionSummary(
                sessionID: session.id,
                windowTitle: session.windowTitle,
                startTime: session.startTime,
                endTime: session.endTime,
                narrative: narrative.narrative,
                keyMoments: narrative.keyMoments,
                entities: narrative.entities,
                modelIdentifier: narrative.modelIdentifier
            )
            summary.meeting = meeting
            meeting.sessionSummaries.append(summary)
            generated += 1
        }
        if generated > 0 {
            PersistenceGate.save(context, site: "ScreenSharePlayer.generateRecaps", meetingID: meeting.id)
        }
        refresh(from: meeting)
        LogManager.shared.log("Recap backfill complete (\(generated) recap(s))", category: .screen, meetingID: meeting.id)
    }

    private func apply(
        _ result: ScreenFrameAnalysisService.BatchResult,
        to meeting: Meeting
    ) {
        var rowsByID: [UUID: ScreenShareFrame] = [:]
        for row in meeting.screenFrames {
            rowsByID[row.id] = row
        }
        for observation in result.observations {
            guard let row = rowsByID[observation.frameID] else { continue }
            row.observation = observation.observation
            row.contentTypeRaw = observation.contentType
            row.keyEntities = observation.keyEntities
            row.analysisState = .analyzed
            row.analysisModelIdentifier = result.modelIdentifier
        }
        for id in result.failedIDs {
            rowsByID[id]?.analysisState = .failed
        }
    }

    /// One-off vision analysis for a frame that never got an observation.
    func analyzeNow(_ frame: FrameItem, meeting: Meeting, context: ModelContext) async {
        guard !analyzingFrameIDs.contains(frame.id) else { return }
        guard let client = await Self.makeVisionClient(meetingID: meeting.id, context: "Analyze-frame") else { return }
        guard let jpegData = try? Data(contentsOf: frame.imageURL) else {
            LogManager.shared.log("Analyze-frame skipped: image file unreadable (\(frame.imageURL.lastPathComponent))", category: .screen, level: .warning, meetingID: meeting.id)
            return
        }
        analyzingFrameIDs.insert(frame.id)
        defer { analyzingFrameIDs.remove(frame.id) }

        let service = ScreenFrameAnalysisService(
            client: client,
            meetingID: meeting.id,
            maxAnalyzedPerMeeting: 1
        )
        let snapshot = ScreenFrameAnalysisService.FrameSnapshot(
            frameID: frame.id,
            sessionID: frame.sessionID,
            timestamp: frame.timestamp,
            formattedTimestamp: frame.formattedTimestamp,
            jpegData: jpegData,
            ocrExcerpt: frame.ocrText,
            isVisualOnlyChange: false
        )
        _ = await service.enqueue([snapshot])
        let topics = meeting.latestInsight?.topics ?? []
        let result = await service.analyzePendingBatch(recentTopics: topics)

        guard let observation = result.observations.first,
              let row = meeting.screenFrames.first(where: { $0.id == frame.id }) else {
            LogManager.shared.log("Analyze-frame returned no observation for #\(frame.formattedTimestamp)", category: .screen, level: .warning, meetingID: meeting.id)
            return
        }
        row.observation = observation.observation
        row.contentTypeRaw = observation.contentType
        row.keyEntities = observation.keyEntities
        row.analysisState = .analyzed
        row.analysisModelIdentifier = result.modelIdentifier
        PersistenceGate.save(context, site: "ScreenSharePlayer.analyzeNow", meetingID: meeting.id)
        refresh(from: meeting)
        LogManager.shared.log("Analyze-frame complete for [\(frame.formattedTimestamp)] (\(observation.contentType))", category: .screen, meetingID: meeting.id)
    }
}
