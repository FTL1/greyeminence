import Foundation
import SwiftData

/// Turns Meeting content (transcript, tasks, follow-ups, summary) into
/// embedding records in the dedicated embedding store. Safe to call
/// repeatedly — upserts by composite id.
@MainActor
final class EmbeddingIndexer {
    let store: EmbeddingStore
    let service: EmbeddingService

    init(store: EmbeddingStore, service: EmbeddingService) {
        self.store = store
        self.service = service
    }

    /// One thing to embed, resolved before any network call happens.
    private struct WorkItem {
        let id: String
        let sourceID: UUID
        let kind: EmbeddingRecord.SourceKind
        /// Text sent to the embedding model — may carry a meeting-title
        /// prefix the display text doesn't.
        let embeddingText: String
        /// Text stored on the record and shown to the user.
        let displayText: String
    }

    /// Embed everything in a single meeting. Writes one SwiftData save at the
    /// end. Returns how many records were written, so a caller running a full
    /// reindex can tell "this meeting had nothing to index" from "every call
    /// to the provider failed".
    /// Outcome of indexing one meeting — enough for a caller to tell "nothing
    /// to do" from "everything failed", which a bare count cannot.
    struct IndexResult: Equatable {
        var written: Int
        var attempted: Int
        var alreadyPresent: Int

        /// Every embed call failed. Distinct from a meeting with no content:
        /// one means the provider is broken, the other means there was nothing
        /// to index.
        var isTotalFailure: Bool { attempted > 0 && written == 0 }
        static let nothingToDo = IndexResult(written: 0, attempted: 0, alreadyPresent: 0)
    }

    @discardableResult
    func indexMeeting(_ meeting: Meeting) async -> Int {
        await index(meeting).written
    }

    /// Index a meeting, embedding only what isn't already stored for the
    /// current model.
    ///
    /// Skipping existing records is what makes a re-run cheap enough to be the
    /// repair mechanism: a meeting that lost nine chunks to throttling gets
    /// those nine re-embedded, not all fifty.
    @discardableResult
    func index(_ meeting: Meeting) async -> IndexResult {
        guard service.isAvailable else { return .nothingToDo }

        // Snapshot every value we need BEFORE the first await. Indexing kicks
        // off from stopRecording, which means the meeting is on screen — and
        // the user can delete it from the list while we're suspended on
        // `service.embed(...)`. After resumption, accessing tombstoned
        // SwiftData properties is at best lossy and at worst a crash.
        let snapshot = MeetingSnapshot(meeting: meeting)
        let allItems = Self.workItems(for: snapshot)
        // No content is a success with nothing to do — distinct from a
        // provider that failed on everything it was given.
        guard !allItems.isEmpty else { return .nothingToDo }

        let existing = store.existingRecordIDs(
            meetingID: snapshot.id,
            modelIdentifier: service.modelIdentifier
        )
        let items = allItems.filter { !existing.contains($0.id) }
        guard !items.isEmpty else {
            return IndexResult(written: 0, attempted: 0, alreadyPresent: allItems.count)
        }

        // One batched call so a network-backed provider can fan out. The
        // on-device provider still runs these strictly serially — its
        // framework aborts the process under concurrent access.
        let vectors = await service.embedAll(items.map(\.embeddingText))

        var indexedFrames = 0
        var written = 0
        for (item, vector) in zip(items, vectors) {
            guard let vector else { continue }
            written += 1
            store.upsert(EmbeddingRecord(
                id: item.id,
                sourceID: item.sourceID,
                sourceKind: item.kind,
                meetingID: snapshot.id,
                meetingTitle: snapshot.title,
                meetingDate: snapshot.date,
                text: item.displayText,
                vector: vector,
                modelIdentifier: service.modelIdentifier
            ))
            if item.kind == .screenObservation { indexedFrames += 1 }
        }
        if !snapshot.screenFrames.isEmpty {
            LogManager.send("Indexed \(indexedFrames)/\(snapshot.screenFrames.count) screen frame(s) for search", category: .screen, meetingID: snapshot.id)
        }

        store.save()
        return IndexResult(
            written: written,
            attempted: items.count,
            alreadyPresent: allItems.count - items.count
        )
    }

    /// How many records a meeting *should* have under the current model.
    /// Pure — no embedding, no network — so the backfill can check coverage
    /// across the whole library cheaply.
    func expectedRecordCount(for meeting: Meeting) -> Int {
        Self.workItems(for: MeetingSnapshot(meeting: meeting)).count
    }

    /// Everything in a meeting that gets a vector, in one flat list.
    ///
    /// Pure and snapshot-driven so the whole set can be handed to the provider
    /// at once — which is what lets a network provider run them concurrently
    /// instead of 34,000 sequential round trips.
    private static func workItems(for snapshot: MeetingSnapshot) -> [WorkItem] {
        var items: [WorkItem] = []

        for chunk in buildTranscriptChunks(segments: snapshot.segments, meetingTitle: snapshot.title) {
            items.append(WorkItem(
                id: "chunk:\(chunk.firstSegmentID)",
                sourceID: chunk.firstSegmentID,
                kind: .transcriptSegment,
                embeddingText: chunk.embeddingText,
                displayText: chunk.displayText
            ))
        }

        for action in snapshot.actionItems {
            items.append(WorkItem(
                id: "action:\(action.id)",
                sourceID: action.id,
                kind: .actionItem,
                embeddingText: action.text,
                displayText: action.text
            ))
        }

        for insight in snapshot.insights {
            if !insight.summary.isEmpty {
                items.append(WorkItem(
                    id: "summary:\(insight.id)",
                    sourceID: insight.id,
                    kind: .meetingSummary,
                    embeddingText: insight.summary,
                    displayText: insight.summary
                ))
            }
            for (i, question) in insight.followUpQuestions.enumerated() {
                items.append(WorkItem(
                    id: "followup:\(insight.id):\(i)",
                    sourceID: insight.id,
                    kind: .followUpQuestion,
                    embeddingText: question,
                    displayText: question
                ))
            }
        }

        for frame in snapshot.screenFrames {
            guard let text = frameEmbeddingText(observation: frame.observation, ocrText: frame.ocrText) else { continue }
            items.append(WorkItem(
                id: "frame:\(frame.id)",
                sourceID: frame.id,
                kind: .screenObservation,
                embeddingText: "Meeting: \(snapshot.title) — screen share\n\(text)",
                displayText: text
            ))
        }

        for summary in snapshot.sessionSummaries where !summary.narrative.isEmpty {
            items.append(WorkItem(
                id: "sessionSummary:\(summary.sessionID.uuidString)",
                sourceID: summary.sessionID,
                kind: .sessionNarrative,
                embeddingText: "Meeting: \(snapshot.title) — screen share recap\n\(summary.narrative)",
                displayText: summary.narrative
            ))
        }

        return items
    }

    /// What gets embedded for a frame: the observation (semantics) plus an
    /// OCR excerpt (literal tokens — ticket numbers, identifiers). OCR-only
    /// frames qualify when the text is substantial enough to be meaningful.
    static func frameEmbeddingText(observation: String?, ocrText: String?) -> String? {
        let ocrExcerpt = ocrText.map { String($0.prefix(300)) }
        if let observation, !observation.isEmpty {
            if let ocrExcerpt, !ocrExcerpt.isEmpty {
                return "\(observation)\n\(ocrExcerpt)"
            }
            return observation
        }
        guard let ocrExcerpt,
              ocrExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { return nil }
        return ocrExcerpt
    }

    struct MeetingSnapshot {
        let id: UUID
        let title: String
        let date: Date
        let segments: [TranscriptSegment]
        let actionItems: [ActionSnapshot]
        let insights: [InsightSnapshot]
        let screenFrames: [FrameSnapshot]
        let sessionSummaries: [SessionSummarySnapshot]

        init(meeting: Meeting) {
            self.id = meeting.id
            self.title = meeting.title
            self.date = meeting.date
            self.segments = meeting.segments
            self.actionItems = meeting.actionItems.map { item in
                let text = item.assignee.map { "\(item.text) (assigned: \($0))" } ?? item.text
                return ActionSnapshot(id: item.id, text: text)
            }
            self.insights = meeting.insights.map {
                InsightSnapshot(id: $0.id, summary: $0.summary, followUpQuestions: $0.followUpQuestions)
            }
            self.screenFrames = meeting.screenFrames.map {
                FrameSnapshot(id: $0.id, observation: $0.observation, ocrText: $0.ocrText)
            }
            self.sessionSummaries = meeting.sessionSummaries.map {
                SessionSummarySnapshot(sessionID: $0.sessionID, narrative: $0.narrative)
            }
        }
    }

    struct SessionSummarySnapshot {
        let sessionID: UUID
        let narrative: String
    }

    struct FrameSnapshot {
        let id: UUID
        let observation: String?
        let ocrText: String?
    }

    struct ActionSnapshot {
        let id: UUID
        let text: String
    }

    struct InsightSnapshot {
        let id: UUID
        let summary: String
        let followUpQuestions: [String]
    }

    /// Full reindex across all meetings in the main store. Call after the user
    /// switches embedding providers or presses "Reindex all".
    enum ReindexOutcome: Sendable, Equatable {
        case completed(meetings: Int)
        /// Nothing was destroyed — the previous index is still intact.
        case unavailable(String)
        /// Aborted mid-run after repeated failures.
        case aborted(String)
    }

    /// Give up after this many meetings produce no vectors at all. A provider
    /// that is misconfigured fails identically on every record, and grinding
    /// through 433 meetings to prove it wastes minutes and fills the log with
    /// hundreds of copies of one error.
    private static let failureAbortThreshold = 3

    /// Rebuild the whole index with the current service.
    ///
    /// Order matters here and it did not used to. The old index is left alone
    /// until the new provider has proved it can actually produce a vector:
    /// a provider that 403s on every call used to leave the user with no index
    /// at all, having deleted a working one before discovering it couldn't
    /// replace it.
    func reindexAll(mainContext: ModelContext, onProgress: @MainActor @escaping (Int, Int) -> Void) async -> ReindexOutcome {
        guard service.isAvailable else {
            return .unavailable("\(service.modelIdentifier) isn't configured.")
        }
        // Canary. One real call, before anything is deleted.
        guard await service.embed("Grey Eminence search index probe") != nil else {
            return .unavailable(
                "Couldn't produce a test vector — the index was left untouched. Check the Activity Log for the provider's error."
            )
        }

        let meetings = (try? mainContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let total = meetings.count
        var consecutiveFailures = 0

        for (i, meeting) in meetings.enumerated() {
            onProgress(i, total)
            let result = await index(meeting)
            if result.isTotalFailure {
                consecutiveFailures += 1
                if consecutiveFailures >= Self.failureAbortThreshold {
                    return .aborted(
                        "Stopped after \(Self.failureAbortThreshold) meetings produced nothing — see the Activity Log. \(i) of \(total) were indexed."
                    )
                }
            } else {
                consecutiveFailures = 0
            }
        }
        onProgress(total, total)

        // Only now that a full index exists is it safe to retire the previous
        // model's records.
        let pruned = store.deleteRecords(notMatchingModel: service.modelIdentifier)
        if pruned > 0 {
            LogManager.send("Reindex: retired \(pruned) record(s) from the previous embedding model", category: .general)
        }
        return .completed(meetings: total)
    }

    // MARK: - Chunking

    struct TranscriptChunk {
        /// First segment in the chunk. Used as the stable id for upsert and as
        /// the anchor for retrieval-time context expansion.
        let firstSegmentID: UUID
        /// Plain conversation text shown in the UI / sent to the LLM.
        let displayText: String
        /// Text actually fed to the embedding model — includes a meeting-title
        /// prefix so topic words are present even in short chunks.
        let embeddingText: String
    }

    /// Target ~paragraph size. NLEmbedding handles a few hundred chars well;
    /// going much larger dilutes the vector and hurts top-k recall.
    private static let chunkTargetChars = 600
    /// One-segment overlap so a topic that spans a chunk boundary still has
    /// at least one chunk containing both sides of the transition.
    private static let chunkOverlapSegments = 1

    static func buildTranscriptChunks(segments: [TranscriptSegment], meetingTitle: String) -> [TranscriptChunk] {
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        guard !sorted.isEmpty else { return [] }

        var chunks: [TranscriptChunk] = []
        var i = 0
        while i < sorted.count {
            var lines: [String] = []
            var charCount = 0
            var j = i
            while j < sorted.count {
                let seg = sorted[j]
                let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { j += 1; continue }
                let line = "\(seg.speaker.displayName): \(text)"
                lines.append(line)
                charCount += line.count
                j += 1
                if charCount >= chunkTargetChars { break }
            }
            guard !lines.isEmpty else { break }
            let display = lines.joined(separator: "\n")
            let embedding = "Meeting: \(meetingTitle)\n\(display)"
            chunks.append(TranscriptChunk(
                firstSegmentID: sorted[i].id,
                displayText: display,
                embeddingText: embedding
            ))
            if j >= sorted.count { break }
            i = max(j - chunkOverlapSegments, i + 1)
        }
        return chunks
    }
}
