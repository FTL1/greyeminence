import AVFoundation
import Foundation

enum DossierAudioExporter {
    enum Failure: LocalizedError {
        case noAudio
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudio: "No saved audio for this meeting."
            case .exportFailed(let message): "Could not write audio: \(message)"
            }
        }
    }

    /// Copy existing mic/system AAC files into `folder` (already compressed).
    @MainActor
    static func copyWholeMeeting(meeting: Meeting, into folder: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        var written: [String] = []
        for (label, base) in [
            ("mic", StorageManager.shared.micAudioURL(for: audioID)),
            ("system", StorageManager.shared.systemAudioURL(for: audioID)),
        ] {
            let chunks = AudioFileWriter.existingChunkURLs(base: base)
            if chunks.count == 1 {
                let dest = folder.appendingPathComponent("\(label).m4a")
                try FileManager.default.copyItem(at: chunks[0], to: dest)
                written.append("audio/\(label).m4a")
            } else if chunks.count > 1 {
                for (index, url) in chunks.enumerated() {
                    let dest = folder.appendingPathComponent(String(format: "%@-part%03d.m4a", label, index))
                    try FileManager.default.copyItem(at: url, to: dest)
                    written.append("audio/\(dest.lastPathComponent)")
                }
            }
        }
        guard !written.isEmpty else { throw Failure.noAudio }
        return written
    }

    /// Concatenate a speaker's time ranges into one AAC file. Bleed from the
    /// other talker can remain — recordings are mixed tracks, not stems.
    @MainActor
    static func compileSpeaker(
        meeting: Meeting,
        speakerName: String,
        to outputURL: URL
    ) async throws {
        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        let offset = meeting.audioStartOffset
        let segments = meeting.segments
            .sorted { $0.startTime < $1.startTime }
            .filter { DossierNaming.namesMatch($0.speaker.displayName, speakerName) }
        guard !segments.isEmpty else { throw Failure.noAudio }

        let mic = AudioFileWriter.existingChunkURLs(base: StorageManager.shared.micAudioURL(for: audioID))
        let system = AudioFileWriter.existingChunkURLs(base: StorageManager.shared.systemAudioURL(for: audioID))

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Failure.exportFailed("Could not create an audio track.") }

        var cursor = CMTime.zero
        var inserted = false
        for (index, segment) in segments.enumerated() {
            let nextStart = index + 1 < segments.count ? segments[index + 1].startTime : nil
            let start = max(0, segment.startTime - offset)
            let end = max(start + 0.4, TranscriptAutoMerge.playbackEnd(segment: segment, nextStart: nextStart) - offset)
            let preferred = segment.speaker.isMe ? mic : system
            let fallback = segment.speaker.isMe ? system : mic
            let urls = preferred.isEmpty ? fallback : preferred
            let catalog = urls.map { (url: $0, duration: duration(of: $0)) }
            let slices = SegmentAudioPlayer.slices(files: catalog, from: start, to: end)
            for slice in slices {
                let asset = AVURLAsset(url: slice.url)
                guard let source = asset.tracks(withMediaType: .audio).first else { continue }
                let scale = asset.duration.timescale == 0 ? 600 : asset.duration.timescale
                let range = CMTimeRange(
                    start: CMTime(seconds: slice.localStart, preferredTimescale: scale),
                    duration: CMTime(seconds: slice.duration, preferredTimescale: scale)
                )
                try track.insertTimeRange(range, of: source, at: cursor)
                cursor = CMTimeAdd(cursor, range.duration)
                inserted = true
            }
        }
        guard inserted else { throw Failure.noAudio }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.exportFailed("No AAC exporter.")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: Failure.exportFailed(session.error?.localizedDescription ?? "export failed"))
                }
            }
        }
    }

    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }
}
