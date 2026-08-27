import Foundation
import SwiftData

/// Re-attributes transcripts that were written before diarization survived
/// re-processing.
///
/// Those transcripts are fine as text — WhisperKit produced them — they just
/// have every remote voice labelled `"Speaker"`, because the swap that
/// installed them tagged segments by audio source alone. Re-running the whole
/// re-transcription to fix that would cost hours of inference to change a
/// label, so this does the cheap half: diarize the audio that is still on
/// disk and relabel in place, leaving the text untouched.
@MainActor
enum SpeakerRepairService {
    /// The label a collapsed transcript uses for every remote voice. Segments
    /// carrying anything else — "Me", "Speaker 2", a person's name — are left
    /// alone, so a repair can't undo a real attribution or a manual edit.
    static let collapsedLabel = "Speaker"

    enum Outcome: Equatable {
        case repaired(voices: Int, segments: Int)
        /// Diarization heard one voice. Numbering it adds nothing over
        /// "Speaker", so the transcript is left as it is.
        case singleVoice
        /// The audio has been pruned by the retention sweep. Nothing to do,
        /// and nothing that can be done.
        case audioUnavailable
        case notCollapsed
        case failed(String)
    }

    /// Meetings that would benefit: collapsed attribution, and audio still on
    /// disk to attribute from.
    static func candidates(in context: ModelContext) -> [Meeting] {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        return meetings.filter { isCollapsed($0) && !systemChunks(for: $0).isEmpty }
    }

    /// True when the transcript has remote speech and none of it is attributed.
    ///
    /// Checked rather than assumed, because a meeting may have been partly
    /// relabelled by hand and re-running should not disturb that.
    static func isCollapsed(_ meeting: Meeting) -> Bool {
        var sawCollapsed = false
        for segment in meeting.segments {
            switch segment.speaker {
            case .me:
                continue
            case .other(let name) where name == collapsedLabel:
                sawCollapsed = true
            case .other:
                // Already attributed to someone — leave the meeting alone.
                return false
            }
        }
        return sawCollapsed
    }

    /// System-audio chunks for a meeting, resolved exactly as re-processing
    /// resolves them — including the window for a meeting split off another's
    /// recording, whose timeline starts at its own first chunk.
    static func systemChunks(for meeting: Meeting) -> [URL] {
        let storage = StorageManager.shared
        let sourceID = meeting.audioSourceMeetingID ?? meeting.id
        let all = AudioFileWriter.existingChunkURLs(base: storage.systemAudioURL(for: sourceID))
        guard !all.isEmpty else { return [] }
        return ReProcessingQueue.chunks(
            all,
            in: meeting.audioStartOffset...(meeting.audioEndOffset ?? .greatestFiniteMagnitude)
        )
    }

    /// Repair one meeting. The transcript's text and timings are never touched.
    static func repair(_ meeting: Meeting, in context: ModelContext) async -> Outcome {
        guard isCollapsed(meeting) else { return .notCollapsed }
        let chunks = systemChunks(for: meeting)
        guard !chunks.isEmpty else { return .audioUnavailable }

        let diarized: [DiarizedSegment]
        let service = SpeakerDiarizationService()
        do {
            try await service.prepare()
            diarized = try await service.diarizeTrack(chunkURLs: chunks)
        } catch is CancellationError {
            return .failed("Cancelled.")
        } catch {
            return .failed(error.localizedDescription)
        }

        let spans = diarized.map {
            SpeakerAlignment.Span(speakerID: $0.speakerID, start: $0.startTime, end: $0.endTime)
        }
        let significant = SpeakerAlignment.significantSpeakerIDs(in: spans)
        guard significant.count > 1 else { return .singleVoice }

        let usable = spans.filter { significant.contains($0.speakerID) }
        let labels = SpeakerAlignment.labels(forSpansOrderedByTime: usable)

        var relabelled = 0
        for segment in meeting.segments {
            guard case .other(let name) = segment.speaker, name == collapsedLabel else { continue }
            guard let id = SpeakerAlignment.dominantSpeakerID(
                from: segment.startTime,
                to: segment.endTime,
                in: usable
            ), let label = labels[id] else { continue }

            // Stash the pre-repair label so this is reversible. Deliberately
            // without setting `isEdited`: that flag means "the user changed
            // this" and drives a badge, and a machine relabel shouldn't claim
            // to be their work. If they later edit the segment themselves, the
            // stash is replaced with the repaired value — which is the right
            // revert target for them anyway.
            if !segment.isEdited, segment.originalSpeakerData == nil {
                segment.originalSpeakerData = segment.speakerData
            }
            segment.speaker = .other(label)
            relabelled += 1
        }
        guard relabelled > 0 else { return .singleVoice }

        PersistenceGate.save(
            context,
            site: "SpeakerRepair.relabel",
            critical: false,
            meetingID: meeting.id
        )
        // Indexed snippets embed the speaker name — "Speaker: we can't turn
        // that on" — so leaving them alone would have Ask quoting the old
        // attribution back at the user. Dropping the records lets the launch
        // backfill re-index the meeting with the names it now has.
        invalidateSearchIndex(for: meeting)
        return .repaired(voices: significant.count, segments: relabelled)
    }

    /// Undo a repair, restoring the labels the transcript had before it.
    ///
    /// Exists because a repair is otherwise one-way: once segments read
    /// "Speaker 2" they no longer look collapsed, so neither this service nor
    /// a future improved diarizer would ever revisit them. Resetting makes the
    /// meeting a candidate again.
    @discardableResult
    static func resetLabels(for meeting: Meeting, in context: ModelContext) -> Int {
        var reverted = 0
        for segment in meeting.segments {
            // Never touch a segment the user edited — their label is not ours
            // to roll back.
            guard !segment.isEdited, let original = segment.originalSpeakerData else { continue }
            segment.speakerData = original
            segment.originalSpeakerData = nil
            reverted += 1
        }
        guard reverted > 0 else { return 0 }
        PersistenceGate.save(
            context,
            site: "SpeakerRepair.reset",
            critical: false,
            meetingID: meeting.id
        )
        invalidateSearchIndex(for: meeting)
        return reverted
    }

    /// True when a repair left something to undo.
    static func canResetLabels(_ meeting: Meeting) -> Bool {
        meeting.segments.contains { !$0.isEdited && $0.originalSpeakerData != nil }
    }

    private static func invalidateSearchIndex(for meeting: Meeting) {
        guard let store = EmbeddingStore.shared else { return }
        let removed = store.deleteRecords(forMeetingID: meeting.id)
        if removed > 0 {
            LogManager.send(
                "Speaker repair: dropped \(removed) search record(s) for \"\(meeting.title)\" so they re-index with the new speakers",
                category: .transcription,
                meetingID: meeting.id
            )
        }
    }

    /// Repair every candidate, oldest first so a long run makes visible
    /// progress through the backlog rather than picking at random.
    static func repairAll(
        in context: ModelContext,
        onProgress: @MainActor (Int, Int) -> Void
    ) async -> (repaired: Int, skipped: Int) {
        let meetings = candidates(in: context).sorted { $0.date < $1.date }
        var repaired = 0
        var skipped = 0

        LogManager.send("Speaker repair: \(meetings.count) meeting(s) with unattributed voices", category: .transcription)
        for (index, meeting) in meetings.enumerated() {
            if Task.isCancelled { break }
            onProgress(index, meetings.count)
            // The diarizer runs on the Neural Engine, which a live recording
            // needs more than a backlog repair does.
            guard ReProcessingQueue.shared.current == nil else {
                LogManager.send("Speaker repair: paused, re-processing is running", category: .transcription)
                break
            }
            switch await repair(meeting, in: context) {
            case .repaired(let voices, let segments):
                repaired += 1
                LogManager.send(
                    "Speaker repair: \"\(meeting.title)\" — \(voices) voices across \(segments) segment(s)",
                    category: .transcription,
                    meetingID: meeting.id
                )
            case .singleVoice, .audioUnavailable, .notCollapsed:
                skipped += 1
            case .failed(let message):
                skipped += 1
                LogManager.send(
                    "Speaker repair failed for \"\(meeting.title)\": \(message)",
                    category: .transcription,
                    level: .warning,
                    meetingID: meeting.id
                )
            }
        }
        onProgress(meetings.count, meetings.count)
        LogManager.send("Speaker repair complete: \(repaired) repaired, \(skipped) skipped", category: .transcription)
        return (repaired, skipped)
    }
}
