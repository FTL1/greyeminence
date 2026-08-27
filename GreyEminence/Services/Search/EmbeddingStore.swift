import Foundation
import SwiftData

/// Thin wrapper around the second `ModelContainer` that owns embeddings.
/// Kept out of the main SwiftData container so the primary store stays simple
/// and so wiping/re-indexing doesn't risk the user's meeting data.
@MainActor
final class EmbeddingStore {
    /// Cached instance, replaced when init succeeds. We retry every access
    /// because failing once at app launch (corrupted file, locked WAL,
    /// transient permission) used to disable Ask + indexing for the rest of
    /// the session with no recovery path.
    private static var cached: EmbeddingStore?
    private static var lastInitError: String?

    static var shared: EmbeddingStore? {
        if let cached { return cached }
        do {
            let instance = try EmbeddingStore()
            cached = instance
            lastInitError = nil
            return instance
        } catch {
            let message = error.localizedDescription
            if lastInitError != message {
                LogManager.send("EmbeddingStore init failed: \(message)", category: .general, level: .error)
                lastInitError = message
            }
            return nil
        }
    }

    /// Surface the most recent failure so Settings can show it and offer a
    /// "Rebuild embedding store" action.
    static var initFailureMessage: String? { lastInitError }

    /// Wipe the on-disk embedding store and clear the cached instance so the
    /// next `shared` access re-creates it. Loses every embedding — caller is
    /// expected to follow up with a reindex.
    static func resetOnDisk() throws {
        cached = nil
        lastInitError = nil
        let url = storeURL()
        let fm = FileManager.default
        // SwiftData writes .store, .store-shm, .store-wal alongside each
        // other; remove the whole sidecar set so the next init starts clean.
        for suffix in ["", "-shm", "-wal"] {
            let candidate = url.deletingPathExtension().appendingPathExtension("store\(suffix)")
            if fm.fileExists(atPath: candidate.path) {
                try fm.removeItem(at: candidate)
            }
        }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    let container: ModelContainer

    init() throws {
        let schema = Schema([EmbeddingRecord.self])
        let url = Self.storeURL()
        let config = ModelConfiguration(
            "GreyEminenceEmbeddings",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    var context: ModelContext { container.mainContext }

    private static func storeURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GreyEminence", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Embeddings.store")
    }

    func upsert(_ record: EmbeddingRecord) {
        let id = record.id
        let existing = try? context.fetch(
            FetchDescriptor<EmbeddingRecord>(predicate: #Predicate { $0.id == id })
        ).first
        if let existing {
            existing.vector = record.vector
            existing.text = record.text
            existing.meetingTitle = record.meetingTitle
            existing.meetingDate = record.meetingDate
            existing.modelIdentifier = record.modelIdentifier
            existing.indexedAt = .now
        } else {
            context.insert(record)
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            LogManager.send("EmbeddingStore save failed: \(error.localizedDescription)", category: .general, level: .error)
        }
    }

    func deleteAll() {
        try? context.delete(model: EmbeddingRecord.self)
        save()
    }

    /// Drop every record NOT produced by `modelIdentifier` — the index only
    /// ever serves one model, so the others are dead weight.
    ///
    /// Named for what it deletes. It was called `deleteRecords(matching:)`
    /// while deleting the complement, which read as a safe no-op at the top of
    /// a reindex and was in fact the line that destroyed the working index.
    @discardableResult
    func deleteRecords(notMatchingModel modelIdentifier: String) -> Int {
        let predicate = #Predicate<EmbeddingRecord> { $0.modelIdentifier != modelIdentifier }
        let count = (try? context.fetchCount(FetchDescriptor<EmbeddingRecord>(predicate: predicate))) ?? 0
        try? context.delete(model: EmbeddingRecord.self, where: predicate)
        save()
        return count
    }

    /// Remove every embedding for a single meeting. Called when the meeting is
    /// deleted (so search doesn't return tombstone hits) and before
    /// re-indexing (so stale chunks from the previous transcription pass don't
    /// linger alongside new ones — the upsert keys on segment UUID, which
    /// changes when re-processing replaces segments).
    @discardableResult
    func deleteRecords(forMeetingID meetingID: UUID) -> Int {
        let predicate = #Predicate<EmbeddingRecord> { $0.meetingID == meetingID }
        let count = (try? context.fetchCount(FetchDescriptor<EmbeddingRecord>(predicate: predicate))) ?? 0
        try? context.delete(model: EmbeddingRecord.self, where: predicate)
        save()
        return count
    }

    /// Remove one record by its composite id (e.g. "frame:<uuid>"). Used when
    /// a single source item (a screen frame) is deleted without touching the
    /// rest of the meeting's embeddings.
    func deleteRecord(id: String) {
        let predicate = #Predicate<EmbeddingRecord> { $0.id == id }
        try? context.delete(model: EmbeddingRecord.self, where: predicate)
        save()
    }

    /// Bulk variant for maintenance — keep only embeddings whose meetingID is
    /// in the supplied set. Returns the number of records pruned.
    @discardableResult
    func deleteRecords(notMatchingMeetingIDs liveIDs: Set<UUID>) -> Int {
        let descriptor = FetchDescriptor<EmbeddingRecord>()
        guard let all = try? context.fetch(descriptor) else { return 0 }
        var pruned = 0
        for record in all where !liveIDs.contains(record.meetingID) {
            context.delete(record)
            pruned += 1
        }
        if pruned > 0 { save() }
        return pruned
    }

    /// Composite ids already present for one meeting under one model.
    ///
    /// Lets indexing fill holes instead of re-embedding a whole meeting, and
    /// lets the backfill tell a fully-indexed meeting from one that lost part
    /// of itself to a throttled request.
    func existingRecordIDs(meetingID: UUID, modelIdentifier: String) -> Set<String> {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate {
                $0.meetingID == meetingID && $0.modelIdentifier == modelIdentifier
            }
        )
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.id))
    }

    func allRecords(for modelIdentifier: String) -> [EmbeddingRecord] {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.modelIdentifier == modelIdentifier }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<EmbeddingRecord>())) ?? 0
    }

    /// Record counts for every meeting under one model, in a single query.
    ///
    /// The launch sweep needs this for the whole library, and asking per
    /// meeting meant several hundred separate round trips. Only the meeting id
    /// is fetched, so nothing else is materialised.
    func recordCountsByMeeting(forModel modelIdentifier: String) -> [UUID: Int] {
        var descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.modelIdentifier == modelIdentifier }
        )
        descriptor.propertiesToFetch = [\.meetingID]
        guard let records = try? context.fetch(descriptor) else { return [:] }
        return records.reduce(into: [UUID: Int]()) { counts, record in
            counts[record.meetingID, default: 0] += 1
        }
    }

    /// How many records a meeting has under one model. A count query — it
    /// never faults the meeting's segments, which is what makes it usable
    /// across the whole library.
    func recordCount(forMeetingID meetingID: UUID, modelIdentifier: String) -> Int {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate {
                $0.meetingID == meetingID && $0.modelIdentifier == modelIdentifier
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Records produced by one embedding model. The total on its own hides a
    /// half-migrated index: after switching methods the store can be full and
    /// the search still find nothing.
    func count(forModel modelIdentifier: String) -> Int {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.modelIdentifier == modelIdentifier }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Quick coverage check used by the header bar to decide whether to show
    /// the "Index this meeting" affordance, and by the backfill scan.
    func recordCount(forMeetingID meetingID: UUID) -> Int {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.meetingID == meetingID }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Set of meeting IDs that have at least one embedding record for the
    /// given model. Used by the launch-time backfill to compute the
    /// complement against the main store's meeting set.
    func indexedMeetingIDs(for modelIdentifier: String) -> Set<UUID> {
        let descriptor = FetchDescriptor<EmbeddingRecord>(
            predicate: #Predicate { $0.modelIdentifier == modelIdentifier }
        )
        let recs = (try? context.fetch(descriptor)) ?? []
        return Set(recs.map(\.meetingID))
    }
}
