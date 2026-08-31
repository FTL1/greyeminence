import AVFoundation
import Foundation

struct AudioPlaySlice: Equatable {
    var url: URL
    var localStart: TimeInterval
    var duration: TimeInterval
}

/// Plays the saved mic or system-audio slice for one transcript line.
/// A merged line plays the full start…end range, walking consecutive
/// on-disk chunks if the recording was split across files.
@Observable
@MainActor
final class SegmentAudioPlayer {
    static let shared = SegmentAudioPlayer()

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    private var remainingSlices: [AudioPlaySlice] = []
    private(set) var playingSegmentID: UUID?

    var isPlaying: Bool { playingSegmentID != nil }

    func isPlaying(_ id: UUID) -> Bool { playingSegmentID == id }

    func toggle(segment: TranscriptSegment, meeting: Meeting, nextStart: TimeInterval? = nil) {
        if playingSegmentID == segment.id {
            stop()
            return
        }
        do {
            try play(segment: segment, meeting: meeting, nextStart: nextStart)
        } catch {
            stop()
            TransientActivityCoordinator.shared.flash(
                "Could not play that line: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        remainingSlices = []
        player?.stop()
        player = nil
        playingSegmentID = nil
    }

    private func play(segment: TranscriptSegment, meeting: Meeting, nextStart: TimeInterval?) throws {
        stop()
        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        let preferred = segment.speaker.isMe
            ? StorageManager.shared.micAudioURL(for: audioID)
            : StorageManager.shared.systemAudioURL(for: audioID)
        var urls = AudioFileWriter.existingChunkURLs(base: preferred)
        if urls.isEmpty {
            let fallback = segment.speaker.isMe
                ? StorageManager.shared.systemAudioURL(for: audioID)
                : StorageManager.shared.micAudioURL(for: audioID)
            urls = AudioFileWriter.existingChunkURLs(base: fallback)
        }
        guard !urls.isEmpty else {
            throw PlaybackError.noAudio
        }

        let offset = meeting.audioStartOffset
        let start = max(0, segment.startTime - offset)
        let end = max(start + 0.4, TranscriptAutoMerge.playbackEnd(segment: segment, nextStart: nextStart) - offset)
        let catalog = urls.map { (url: $0, duration: Self.duration(of: $0)) }
        let slices = Self.slices(files: catalog, from: start, to: end)
        guard !slices.isEmpty else { throw PlaybackError.noAudio }

        remainingSlices = slices
        playingSegmentID = segment.id
        try playNextSlice()
    }

    private func playNextSlice() throws {
        guard let slice = remainingSlices.first else {
            stop()
            return
        }
        remainingSlices.removeFirst()
        let player = try AVAudioPlayer(contentsOf: slice.url)
        player.currentTime = min(slice.localStart, max(0, player.duration - 0.05))
        guard player.play() else { throw PlaybackError.failed }
        self.player = player

        let playFor = min(slice.duration, max(0.05, player.duration - player.currentTime))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.remainingSlices.isEmpty {
                self.stop()
            } else {
                try? self.playNextSlice()
            }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + playFor, execute: work)
    }

    /// Clip `[start, end)` onto a sequence of files laid out end-to-end.
    nonisolated static func slices(
        files: [(url: URL, duration: TimeInterval)],
        from start: TimeInterval,
        to end: TimeInterval
    ) -> [AudioPlaySlice] {
        guard end > start else { return [] }
        var cursor: TimeInterval = 0
        var result: [AudioPlaySlice] = []
        for file in files {
            let fileStart = cursor
            let fileEnd = cursor + max(0, file.duration)
            cursor = fileEnd
            let overlapStart = max(start, fileStart)
            let overlapEnd = min(end, fileEnd)
            if overlapEnd > overlapStart + 0.01 {
                result.append(
                    AudioPlaySlice(
                        url: file.url,
                        localStart: overlapStart - fileStart,
                        duration: overlapEnd - overlapStart
                    )
                )
            }
            if cursor >= end { break }
        }
        return result
    }

    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    enum PlaybackError: LocalizedError {
        case noAudio
        case failed

        var errorDescription: String? {
            switch self {
            case .noAudio: "No saved audio for this line."
            case .failed: "The audio file would not play."
            }
        }
    }
}
