import Foundation

@Observable
final class StorageManager: Sendable {
    static let shared = StorageManager()

    let appSupportURL: URL
    let recordingsURL: URL
    let modelsURL: URL
    let candidatesURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GreyEminence", isDirectory: true)
        self.appSupportURL = base
        self.recordingsURL = base.appendingPathComponent("Recordings", isDirectory: true)
        self.modelsURL = base.appendingPathComponent("Models", isDirectory: true)
        self.candidatesURL = base.appendingPathComponent("Candidates", isDirectory: true)

        for url in [base, recordingsURL, modelsURL, candidatesURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func recordingDirectory(for meetingID: UUID) -> URL {
        let dir = recordingsURL.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func micAudioURL(for meetingID: UUID) -> URL {
        recordingDirectory(for: meetingID).appendingPathComponent("mic.m4a")
    }

    func systemAudioURL(for meetingID: UUID) -> URL {
        recordingDirectory(for: meetingID).appendingPathComponent("system.m4a")
    }

    /// Remove the entire recording directory for a meeting (mic + system
    /// chunks, plus any sidecar files). Returns true if something was
    /// actually removed. Missing-file is not an error.
    @discardableResult
    func deleteRecording(for meetingID: UUID) -> Bool {
        let dir = recordingsURL.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: dir)
            return true
        } catch CocoaError.fileNoSuchFile {
            return false
        } catch {
            return false
        }
    }

    /// Sweep the Recordings directory and remove any per-meeting folder whose
    /// UUID isn't referenced by the provided set (meeting IDs +
    /// `audioSourceMeetingID` of split meetings). Returns the number of
    /// directories removed and the total bytes freed.
    func purgeOrphanedRecordings(referencedIDs: Set<UUID>) -> (count: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: recordingsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var count = 0
        var bytes: Int64 = 0
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, let uuid = UUID(uuidString: entry.lastPathComponent) else { continue }
            if referencedIDs.contains(uuid) { continue }

            let size = directorySize(at: entry)
            do {
                try fm.removeItem(at: entry)
                count += 1
                bytes += size
            } catch {
                // Skip on failure; next launch will try again.
            }
        }
        return (count, bytes)
    }

    // MARK: - Candidate Resumes

    /// Per-candidate directory for attached files (currently just resumes).
    /// Created lazily on first access.
    func candidateDirectory(for candidateID: UUID) -> URL {
        let dir = candidatesURL.appendingPathComponent(candidateID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Resolved on-disk URL for a candidate's resume, given the stored
    /// filename. Doesn't check existence — callers should verify with
    /// `FileManager.default.fileExists(atPath:)` before using.
    func candidateResumeURL(for candidateID: UUID, filename: String) -> URL {
        candidateDirectory(for: candidateID).appendingPathComponent(filename)
    }

    /// Copy a user-picked file into the candidate's directory and return
    /// the destination filename. Replaces any prior resume to avoid orphan
    /// files. The source URL must already have its security scope started
    /// by the caller; we just read from it during the copy.
    @discardableResult
    func attachResume(sourceURL: URL, candidateID: UUID, replacingFilename: String?) throws -> String {
        let dir = candidateDirectory(for: candidateID)
        // Drop any pre-existing resume for this candidate so we don't leak
        // disk on replacement. Cheap enough — typical candidate has 0 or 1.
        if let prior = replacingFilename {
            let priorURL = dir.appendingPathComponent(prior)
            try? FileManager.default.removeItem(at: priorURL)
        }
        // Sanitize filename: strip path separators (defensive — shouldn't
        // happen via NSOpenPanel but a malformed bookmark could).
        let baseName = sourceURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let destURL = dir.appendingPathComponent(baseName)
        // If a file of the same name already exists from a half-broken
        // earlier attach, remove it before copying so the copy doesn't fail.
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return baseName
    }

    /// Remove a candidate's resume file and clean up the candidate
    /// directory if it's now empty.
    @discardableResult
    func removeResume(candidateID: UUID, filename: String) -> Bool {
        let dir = candidateDirectory(for: candidateID)
        let url = dir.appendingPathComponent(filename)
        let removed = (try? FileManager.default.removeItem(at: url)) != nil
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path), entries.isEmpty {
            try? FileManager.default.removeItem(at: dir)
        }
        return removed
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }
}
