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
    /// Consecutive meetings that may produce nothing before the sweep gives
    /// up. Mirrors the full reindex's threshold, for the same reason.
    private static let failureAbortThreshold = 3

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

        let meetings = (try? mainContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let indexer = EmbeddingIndexer(store: store, service: service)
        // Coverage is counted per record, not per meeting. Meeting-level
        // coverage treated a meeting with one chunk of fifty as done, so a
        // throttled run left 9,154 chunks missing that no later sweep would
        // ever look at — the store reported every meeting indexed while a
        // third of the content was unsearchable.
        let missing = meetings.filter { meeting in
            guard meeting.status == .completed,
                  !meeting.segments.isEmpty,
                  meeting.reProcessingState == nil else { return false }
            let present = store.existingRecordIDs(
                meetingID: meeting.id,
                modelIdentifier: service.modelIdentifier
            ).count
            return present < indexer.expectedRecordCount(for: meeting)
        }
        guard !missing.isEmpty else {
            LogManager.send(
                "EmbeddingBackfill: nothing to do — every meeting fully indexed for \(service.modelIdentifier)",
                category: .general
            )
            return
        }

        LogManager.send(
            "EmbeddingBackfill: \(missing.count) meeting(s) missing records for \(service.modelIdentifier)",
            category: .general
        )
        // The count lives in the progress readout now, so the label just names
        // the work. A backfill of several hundred meetings runs for minutes —
        // long enough that a bare spinner reads as a hang.
        let label = "Indexing meetings for search…"
        var aborted = false
        await TransientActivityCoordinator.shared.runAsync(label) {
            let coordinator = TransientActivityCoordinator.shared
            coordinator.setProgress(completed: 0, total: missing.count)
            var consecutiveFailures = 0
            for (index, meeting) in missing.enumerated() {
                // Re-check mid-loop: a reprocess might have started, or the
                // meeting might have been deleted by the user. Indexing a
                // tombstoned meeting accesses lazy SwiftData properties
                // that will trap.
                defer { coordinator.setProgress(completed: index + 1, total: missing.count) }
                guard meeting.reProcessingState == nil else { continue }
                let result = await indexer.index(meeting)
                guard result.isTotalFailure else {
                    consecutiveFailures = 0
                    continue
                }
                consecutiveFailures += 1
                // An expired token or a revoked permission fails identically
                // on every record. Grinding through hundreds of meetings to
                // prove it burns requests and buries the one useful line in
                // the log under hundreds of copies of itself.
                if consecutiveFailures >= Self.failureAbortThreshold {
                    aborted = true
                    return
                }
            }
        }
        if aborted {
            LogManager.send(
                "EmbeddingBackfill: stopped — \(Self.failureAbortThreshold) meetings in a row produced nothing. See the errors above.",
                category: .general,
                level: .warning
            )
            TransientActivityCoordinator.shared.flash("Search indexing stopped — check Settings → Ask")
        } else {
            LogManager.send("EmbeddingBackfill: complete", category: .general)
        }
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
