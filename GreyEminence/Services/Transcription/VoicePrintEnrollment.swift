import Foundation
import SwiftData

/// Pull a speaker embedding out of a meeting's saved audio and write it
/// onto a Contact. Live sessions prefer the in-memory diarizer snapshot
/// and only fall back to this when that snapshot is missing.
enum VoicePrintEnrollment {
    enum EnrollmentError: LocalizedError {
        case notEnoughAudio
        case noRecording
        case extractionFailed
        case needsPerson

        var errorDescription: String? {
            switch self {
            case .notEnoughAudio:
                "Not enough audio yet — let them talk a few more seconds, then try again."
            case .noRecording:
                "No recording on disk to enroll from."
            case .extractionFailed:
                "Could not extract a voice print from this audio."
            case .needsPerson:
                "Pick someone in This meeting or Prior speakers first."
            }
        }
    }

    struct Request: Sendable {
        var audioBaseURL: URL
        var ranges: [(start: TimeInterval, end: TimeInterval)]
        var audioOffset: TimeInterval
    }

    static func request(
        for speaker: Speaker,
        in meeting: Meeting,
        segments: [TranscriptSegment]
    ) -> Request? {
        let theirs = segments.filter { $0.speaker.matchesIdentity(speaker) && $0.isFinal }
        guard !theirs.isEmpty else { return nil }
        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        let base = speaker.isMe
            ? StorageManager.shared.micAudioURL(for: audioID)
            : StorageManager.shared.systemAudioURL(for: audioID)
        let ranges = theirs.prefix(40).map { ($0.startTime, $0.endTime) }
        return Request(audioBaseURL: base, ranges: Array(ranges), audioOffset: meeting.audioStartOffset)
    }

    static func extractEmbedding(_ request: Request) async throws -> [Float] {
        let samples = try sliceSamples(request)
        guard samples.count >= 48_000 else { throw EnrollmentError.notEnoughAudio }
        let service = SpeakerDiarizationService()
        try await service.prepare()
        guard let embedding = try await service.extractDominantEmbedding(from: samples) else {
            throw EnrollmentError.extractionFailed
        }
        return embedding
    }

    static func resolveContact(
        for speaker: Speaker,
        contacts: [Contact],
        mapped: Contact?
    ) -> Contact? {
        if let mapped { return mapped }
        if speaker.isMe, let myID = Meeting.storedMyContactID {
            if let me = contacts.first(where: { $0.id == myID }) { return me }
        }
        if speaker.isGuestPlaceholder { return nil }
        return contacts.first { $0.matchesSpeakerName(speaker.displayName) }
    }

    private static func sliceSamples(_ request: Request) throws -> [Float] {
        var full: [Float] = []
        let urls = AudioFileWriter.existingChunkURLs(base: request.audioBaseURL)
        guard !urls.isEmpty else { throw EnrollmentError.noRecording }
        for url in urls {
            if let chunk = try? HighQualityTranscriber.decodeFileTo16kFloatMono(url: url) {
                full.append(contentsOf: chunk)
            }
        }
        guard !full.isEmpty else { throw EnrollmentError.noRecording }

        let rate: Double = 16_000
        var sliced: [Float] = []
        sliced.reserveCapacity(16_000 * 12)
        for range in request.ranges {
            let start = max(0, Int((range.start - request.audioOffset) * rate))
            let end = min(full.count, Int((range.end - request.audioOffset) * rate))
            guard end > start else { continue }
            sliced.append(contentsOf: full[start..<end])
            if sliced.count >= 16_000 * 30 { break }
        }
        if sliced.count < 48_000, full.count >= 48_000 {
            return Array(full.prefix(16_000 * 20))
        }
        return sliced
    }
}
