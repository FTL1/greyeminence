import Foundation
import SwiftData

@MainActor
enum MeetingDeletion {
    /// A split meeting references its parent's audio via `audioSourceMeetingID`,
    /// so the parent's recording directory must not be removed while any other
    /// meeting still points at it. Pass `allMeetings` if you already have the
    /// list; otherwise it'll be fetched from `context`.
    static func delete(_ meeting: Meeting, in context: ModelContext, allMeetings: [Meeting]? = nil) {
        let meetingID = meeting.id
        let audioSourceID = meeting.audioSourceMeetingID ?? meetingID
        let others = allMeetings ?? ((try? context.fetch(FetchDescriptor<Meeting>())) ?? [])

        // Capture this meeting's frame image paths BEFORE the cascade delete
        // wipes the rows — they're needed to clean the JPEGs from disk if the
        // recording directory ends up retained for a split sibling below.
        let framePaths = meeting.screenFrames.map(\.imagePath)

        context.delete(meeting)
        PersistenceGate.save(context, site: "MeetingDeletion.delete", meetingID: meetingID)

        if let store = EmbeddingStore.shared {
            let removed = store.deleteRecords(forMeetingID: meetingID)
            if removed > 0 {
                LogManager.send("Removed \(removed) embedding(s) for deleted meeting \(meetingID)", category: .general)
            }
        }

        let stillReferenced = others.contains { other in
            guard other.id != meetingID else { return false }
            let otherSource = other.audioSourceMeetingID ?? other.id
            return otherSource == audioSourceID
        }

        if stillReferenced {
            // The recording directory must stay for the sibling's shared audio,
            // so we can't drop the whole folder. But this meeting's frame JPEGs
            // are no longer referenced by any row — remove just those files so
            // they don't linger until the entire audio group is deleted.
            if !framePaths.isEmpty {
                let removedFrames = StorageManager.shared.deleteFrameFiles(
                    sourceMeetingID: audioSourceID,
                    relativePaths: framePaths
                )
                if removedFrames > 0 {
                    LogManager.send("Removed \(removedFrames) orphaned screen-frame file(s) for deleted meeting \(meetingID); audio kept for \(audioSourceID)", category: .general)
                }
            }
            LogManager.send("Deleted meeting \(meetingID); keeping audio for \(audioSourceID) (referenced by another meeting)", category: .general)
            return
        }

        if StorageManager.shared.deleteRecording(for: audioSourceID) {
            LogManager.send("Deleted meeting \(meetingID) and audio files", category: .general)
        }
    }
}
