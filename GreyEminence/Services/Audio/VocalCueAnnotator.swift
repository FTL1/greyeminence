import AVFoundation
import Foundation

/// Measures vocal energy on stored audio slices so Deepest analysis can
/// see emphasis the transcript dropped. Labels are energy, not invented
/// emotions.
enum VocalCueAnnotator {
    struct Cue: Sendable, Equatable {
        var timestamp: String
        var speaker: String
        var text: String
        var relativeEnergy: Double
    }

    @MainActor
    static func cues(for meeting: Meeting, limit: Int = 24) -> [Cue] {
        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        let offset = meeting.audioStartOffset
        let sorted = meeting.segments.sorted { $0.startTime < $1.startTime }
        let sample = sorted.count > 250 ? Array(sorted.prefix(250)) : sorted
        var raw: [(Cue, Double, String)] = []
        for (index, segment) in sample.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 12 else { continue }
            let nextStart = index + 1 < sample.count ? sample[index + 1].startTime : nil
            let start = max(0, segment.startTime - offset)
            let end = max(start + 0.3, TranscriptAutoMerge.playbackEnd(segment: segment, nextStart: nextStart) - offset)
            guard let rms = rms(meetingID: audioID, speakerIsMe: segment.speaker.isMe, start: start, end: end) else {
                continue
            }
            raw.append((
                Cue(timestamp: segment.formattedTimestamp, speaker: segment.speaker.displayName, text: text, relativeEnergy: 1),
                rms,
                segment.speaker.displayName
            ))
        }
        let bySpeaker = Dictionary(grouping: raw, by: { $0.2 })
        var medians: [String: Double] = [:]
        for (speaker, rows) in bySpeaker {
            let values = rows.map(\.1).sorted()
            guard !values.isEmpty else { continue }
            medians[speaker] = values[values.count / 2]
        }
        var scored: [Cue] = []
        for (cue, rms, speaker) in raw {
            let median = medians[speaker] ?? rms
            guard median > 0 else { continue }
            let relative = rms / median
            guard relative >= 1.35 || relative <= 0.45 else { continue }
            scored.append(Cue(timestamp: cue.timestamp, speaker: cue.speaker, text: cue.text, relativeEnergy: relative))
        }
        return Array(
            scored.sorted { abs($0.relativeEnergy - 1) > abs($1.relativeEnergy - 1) }.prefix(limit)
        ).sorted { $0.timestamp < $1.timestamp }
    }

    static func promptBlock(_ cues: [Cue]) -> String {
        guard !cues.isEmpty else { return "" }
        var lines = [
            "VOCAL ENERGY (measured from the saved audio, not guessed):",
            "relative_energy is vs that speaker's median in this meeting. >1.35 = louder/more intense than their norm; <0.45 = quieter. Do NOT invent emotion words (frustration, excitement) unless the WORDS also support them. Use energy only as a weight on importance.",
        ]
        for cue in cues {
            let tag = cue.relativeEnergy >= 1.35 ? "elevated" : "quiet"
            let energy = String(format: "%.2f", cue.relativeEnergy)
            let clip = cue.text.count > 140 ? String(cue.text.prefix(140)) + "…" : cue.text
            lines.append("- [\(cue.timestamp)] \(cue.speaker) (\(tag), \(energy)×): \(clip)")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func rms(meetingID: UUID, speakerIsMe: Bool, start: TimeInterval, end: TimeInterval) -> Double? {
        let preferred = speakerIsMe
            ? StorageManager.shared.micAudioURL(for: meetingID)
            : StorageManager.shared.systemAudioURL(for: meetingID)
        var urls = AudioFileWriter.existingChunkURLs(base: preferred)
        if urls.isEmpty {
            let fallback = speakerIsMe
                ? StorageManager.shared.systemAudioURL(for: meetingID)
                : StorageManager.shared.micAudioURL(for: meetingID)
            urls = AudioFileWriter.existingChunkURLs(base: fallback)
        }
        guard !urls.isEmpty else { return nil }
        let catalog = urls.map { (url: $0, duration: fileDuration($0)) }
        let slices = SegmentAudioPlayer.slices(files: catalog, from: start, to: min(end, start + 0.5))
        guard let slice = slices.first else { return nil }
        return readRMS(url: slice.url, localStart: slice.localStart, duration: min(slice.duration, 0.4))
    }

    private static func fileDuration(_ url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    private static func readRMS(url: URL, localStart: TimeInterval, duration: TimeInterval) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        let startFrame = AVAudioFramePosition(max(0, localStart) * rate)
        let frames = AVAudioFrameCount(max(0.05, duration) * rate)
        guard startFrame < file.length else { return nil }
        file.framePosition = startFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        let count = Int(buffer.frameLength)
        guard count > 16 else { return nil }
        if let samples = buffer.floatChannelData?.pointee {
            var sum: Double = 0
            for i in 0..<count { sum += Double(samples[i] * samples[i]) }
            return sqrt(sum / Double(count))
        }
        return nil
    }
}
