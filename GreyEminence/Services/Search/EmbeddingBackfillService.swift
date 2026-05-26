import Foundation
import SwiftData

/// Heals embedding-store gaps caused by silent skips: meetings whose
/// post-recording indexing pass was killed (crash, force quit) or that
/// predate the indexer entirely. Without this, an un-indexed meeting
/// stays invisible to Ask forever — the only existing recovery was the
/// nuclear "Reindex all" button in Settings, which re-embeds everything.
///
/// Runs once shortly after launch, finds meetings with segments that
/// have zero embedding records for the current model, and indexes just
/// those. Idempotent — safe to call again, will no-op when the store is
/// already fully covered.
@MainActor
enum EmbeddingBackfillService {
    /// Schedule the backfill to run after the UI has settled. Non-blocking;
    /// call from `onAppear`. The delay keeps it out of the way of the
    /// initial render and any reprocess queue ticks that fire at launch.
    static func scheduleAtLaunch(mainContext: ModelContext, delaySeconds: UInt64 = 5) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            await runNow(mainContext: mainContext)
        }
    }

    /// Run the scan + index now. Surfaces via TransientActivityCoordinator
    /// only when there's actual work to do, so the footer stays quiet on
    /// the common "already covered" path.
    static func runNow(mainContext: ModelContext) async {
        guard let store = EmbeddingStore.shared else { return }
        let providerRaw = UserDefaults.standard.string(forKey: "embeddingProvider")
            ?? EmbeddingProvider.nlEmbedding.rawValue
        let provider = EmbeddingProvider(rawValue: providerRaw) ?? .nlEmbedding
        let service = provider.makeService()
        guard service.isAvailable else {
            LogManager.send(
                "EmbeddingBackfill: provider \(provider.shortLabel) unavailable, skipping",
                category: .general
            )
            return
        }

        let indexedIDs = store.indexedMeetingIDs(for: service.modelIdentifier)
        let meetings = (try? mainContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let missing = meetings.filter { meeting in
            meeting.status == .completed
                && !meeting.segments.isEmpty
                && meeting.reProcessingState == nil
                && !indexedIDs.contains(meeting.id)
        }
        guard !missing.isEmpty else {
            LogManager.send(
                "EmbeddingBackfill: nothing to do — \(indexedIDs.count) meetings already indexed for \(service.modelIdentifier)",
                category: .general
            )
            return
        }

        LogManager.send(
            "EmbeddingBackfill: indexing \(missing.count) un-covered meeting(s)",
            category: .general
        )
        let label = "Indexing \(missing.count) meeting\(missing.count == 1 ? "" : "s") for search…"
        await TransientActivityCoordinator.shared.runAsync(label) {
            let indexer = EmbeddingIndexer(store: store, service: service)
            for meeting in missing {
                // Re-check mid-loop: a reprocess might have started, or the
                // meeting might have been deleted by the user. Indexing a
                // tombstoned meeting accesses lazy SwiftData properties
                // that will trap.
                guard meeting.reProcessingState == nil else { continue }
                await indexer.indexMeeting(meeting)
            }
        }
        LogManager.send("EmbeddingBackfill: complete", category: .general)
    }

    /// Index a single meeting on demand, used by the per-meeting "Index"
    /// button in the header bar. Returns the embedding-record count after
    /// the pass so the caller can refresh its coverage state.
    @discardableResult
    static func indexSingleMeeting(_ meeting: Meeting) async -> Int {
        guard let store = EmbeddingStore.shared else { return 0 }
        let providerRaw = UserDefaults.standard.string(forKey: "embeddingProvider")
            ?? EmbeddingProvider.nlEmbedding.rawValue
        let provider = EmbeddingProvider(rawValue: providerRaw) ?? .nlEmbedding
        let service = provider.makeService()
        guard service.isAvailable else { return store.recordCount(forMeetingID: meeting.id) }
        let indexer = EmbeddingIndexer(store: store, service: service)
        await indexer.indexMeeting(meeting)
        return store.recordCount(forMeetingID: meeting.id)
    }
}
