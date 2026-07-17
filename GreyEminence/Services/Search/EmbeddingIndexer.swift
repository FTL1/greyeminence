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

    /// Embed everything in a single meeting. Writes one SwiftData save at the end.
    func indexMeeting(_ meeting: Meeting) async {
        guard service.isAvailable else { return }

        // Snapshot every value we need BEFORE the first await. Indexing kicks
        // off from stopRecording, which means the meeting is on screen — and
        // the user can delete it from the list while we're suspended on
        // `service.embed(...)`. After resumption, accessing tombstoned
        // SwiftData properties is at best lossy and at worst a crash.
        let snapshot = MeetingSnapshot(meeting: meeting)

        for chunk in Self.buildTranscriptChunks(segments: snapshot.segments, meetingTitle: snapshot.title) {
            guard let vec = await service.embed(chunk.embeddingText) else { continue }
            let record = EmbeddingRecord(
                id: "chunk:\(chunk.firstSegmentID)",
                sourceID: chunk.firstSegmentID,
                sourceKind: .transcriptSegment,
                meetingID: snapshot.id,
                meetingTitle: snapshot.title,
                meetingDate: snapshot.date,
                text: chunk.displayText,
                vector: vec,
                modelIdentifier: service.modelIdentifier
            )
            store.upsert(record)
        }

        for action in snapshot.actionItems {
            guard let vec = await service.embed(action.text) else { continue }
            let record = EmbeddingRecord(
                id: "action:\(action.id)",
                sourceID: action.id,
                sourceKind: .actionItem,
                meetingID: snapshot.id,
                meetingTitle: snapshot.title,
                meetingDate: snapshot.date,
                text: action.text,
                vector: vec,
                modelIdentifier: service.modelIdentifier
            )
            store.upsert(record)
        }

        for insight in snapshot.insights {
            if !insight.summary.isEmpty, let vec = await service.embed(insight.summary) {
                let record = EmbeddingRecord(
                    id: "summary:\(insight.id)",
                    sourceID: insight.id,
                    sourceKind: .meetingSummary,
                    meetingID: snapshot.id,
                    meetingTitle: snapshot.title,
                    meetingDate: snapshot.date,
                    text: insight.summary,
                    vector: vec,
                    modelIdentifier: service.modelIdentifier
                )
                store.upsert(record)
            }
            for (i, question) in insight.followUpQuestions.enumerated() {
                guard let vec = await service.embed(question) else { continue }
                let record = EmbeddingRecord(
                    id: "followup:\(insight.id):\(i)",
                    sourceID: insight.id,
                    sourceKind: .followUpQuestion,
                    meetingID: snapshot.id,
                    meetingTitle: snapshot.title,
                    meetingDate: snapshot.date,
                    text: question,
                    vector: vec,
                    modelIdentifier: service.modelIdentifier
                )
                store.upsert(record)
            }
        }

        var indexedFrames = 0
        for frame in snapshot.screenFrames {
            guard let text = Self.frameEmbeddingText(observation: frame.observation, ocrText: frame.ocrText) else { continue }
            guard let vec = await service.embed("Meeting: \(snapshot.title) — screen share\n\(text)") else { continue }
            let record = EmbeddingRecord(
                id: "frame:\(frame.id)",
                sourceID: frame.id,
                sourceKind: .screenObservation,
                meetingID: snapshot.id,
                meetingTitle: snapshot.title,
                meetingDate: snapshot.date,
                text: text,
                vector: vec,
                modelIdentifier: service.modelIdentifier
            )
            store.upsert(record)
            indexedFrames += 1
        }
        if !snapshot.screenFrames.isEmpty {
            LogManager.send("Indexed \(indexedFrames)/\(snapshot.screenFrames.count) screen frame(s) for search", category: .screen, meetingID: snapshot.id)
        }

        store.save()
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

    private struct MeetingSnapshot {
        let id: UUID
        let title: String
        let date: Date
        let segments: [TranscriptSegment]
        let actionItems: [ActionSnapshot]
        let insights: [InsightSnapshot]
        let screenFrames: [FrameSnapshot]

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
        }
    }

    private struct FrameSnapshot {
        let id: UUID
        let observation: String?
        let ocrText: String?
    }

    private struct ActionSnapshot {
        let id: UUID
        let text: String
    }

    private struct InsightSnapshot {
        let id: UUID
        let summary: String
        let followUpQuestions: [String]
    }

    /// Full reindex across all meetings in the main store. Call after the user
    /// switches embedding providers or presses "Reindex all".
    func reindexAll(mainContext: ModelContext, onProgress: @MainActor @escaping (Int, Int) -> Void) async {
        store.deleteRecords(matching: service.modelIdentifier)

        let meetings = (try? mainContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let total = meetings.count
        for (i, meeting) in meetings.enumerated() {
            onProgress(i, total)
            await indexMeeting(meeting)
        }
        onProgress(total, total)
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
