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
        let meetingID = meeting.id
        let title = meeting.title
        let date = meeting.date

        // Embedding short transcript segments individually produced terrible
        // results: tiny phrases like "What is it?" cluster by question pattern
        // rather than topic, drowning real matches. Chunk consecutive segments
        // into ~paragraph-sized units with speaker labels + a meeting-title
        // prefix so embeddings carry actual semantic content.
        for chunk in Self.buildTranscriptChunks(segments: meeting.segments, meetingTitle: title) {
            guard let vec = await service.embed(chunk.embeddingText) else { continue }
            let record = EmbeddingRecord(
                id: "chunk:\(chunk.firstSegmentID)",
                sourceID: chunk.firstSegmentID,
                sourceKind: .transcriptSegment,
                meetingID: meetingID,
                meetingTitle: title,
                meetingDate: date,
                text: chunk.displayText,
                vector: vec,
                modelIdentifier: service.modelIdentifier
            )
            store.upsert(record)
        }

        for item in meeting.actionItems {
            let text = item.assignee.map { "\(item.text) (assigned: \($0))" } ?? item.text
            guard let vec = await service.embed(text) else { continue }
            let record = EmbeddingRecord(
                id: "action:\(item.id)",
                sourceID: item.id,
                sourceKind: .actionItem,
                meetingID: meetingID,
                meetingTitle: title,
                meetingDate: date,
                text: text,
                vector: vec,
                modelIdentifier: service.modelIdentifier
            )
            store.upsert(record)
        }

        for insight in meeting.insights {
            if !insight.summary.isEmpty, let vec = await service.embed(insight.summary) {
                let record = EmbeddingRecord(
                    id: "summary:\(insight.id)",
                    sourceID: insight.id,
                    sourceKind: .meetingSummary,
                    meetingID: meetingID,
                    meetingTitle: title,
                    meetingDate: date,
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
                    meetingID: meetingID,
                    meetingTitle: title,
                    meetingDate: date,
                    text: question,
                    vector: vec,
                    modelIdentifier: service.modelIdentifier
                )
                store.upsert(record)
            }
        }

        store.save()
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
