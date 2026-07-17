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

    private(set) var frames: [FrameItem] = []
    private(set) var sessions: [ShareSession] = []
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
    /// window").
    func deleteSession(_ sessionID: UUID, meeting: Meeting, context: ModelContext) {
        let ids = Set(frames.filter { $0.sessionID == sessionID }.map(\.id))
        deleteFrames(ids: ids, meeting: meeting, context: context)
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
        guard let client = try? await AIClientFactory.makeClient(), client.supportsImages else {
            LogManager.shared.log("Frame backfill skipped: AI not configured or no image support", category: .screen, level: .warning, meetingID: meeting.id)
            return
        }
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

            apply(result, to: meeting, modelIdentifier: client.modelIdentifier)
            done += result.observations.count
            bulkProgress = (done, budget)
        }

        PersistenceGate.save(context, site: "ScreenSharePlayer.analyzeAllFrames", meetingID: meeting.id)
        refresh(from: meeting)
        LogManager.shared.log("Backfilled \(done) frame observation(s)", category: .screen, meetingID: meeting.id)
    }

    private func apply(
        _ result: ScreenFrameAnalysisService.BatchResult,
        to meeting: Meeting,
        modelIdentifier: String
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
            row.analysisModelIdentifier = modelIdentifier
        }
        for id in result.failedIDs {
            rowsByID[id]?.analysisState = .failed
        }
    }

    /// One-off vision analysis for a frame that never got an observation.
    func analyzeNow(_ frame: FrameItem, meeting: Meeting, context: ModelContext) async {
        guard !analyzingFrameIDs.contains(frame.id) else { return }
        guard let client = try? await AIClientFactory.makeClient(), client.supportsImages else {
            LogManager.shared.log("Analyze-frame skipped: AI not configured or no image support", category: .screen, level: .warning, meetingID: meeting.id)
            return
        }
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
        row.analysisModelIdentifier = client.modelIdentifier
        PersistenceGate.save(context, site: "ScreenSharePlayer.analyzeNow", meetingID: meeting.id)
        refresh(from: meeting)
        LogManager.shared.log("Analyze-frame complete for [\(frame.formattedTimestamp)] (\(observation.contentType))", category: .screen, meetingID: meeting.id)
    }
}
