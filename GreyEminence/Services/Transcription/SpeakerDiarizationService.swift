import Foundation
import AVFoundation
import FluidAudio

actor SpeakerDiarizationService {
    enum State: Sendable {
        case uninitialized
        case downloading
        case ready
        case processing
        case error(String)
    }

    private(set) var state: State = .uninitialized

    private var diarizer: DiarizerManager?
    private var audioStream: AudioStream?
    private var audioConverter: AudioConverter?
    private var speakerMap: [String: Speaker] = [:]
    private var voicePrints: [(speaker: Speaker, embedding: [Float])] = []
    /// Cross-meeting prints loaded from Contacts. Survive startStreaming/reset.
    private var enrolledPrints: [(speaker: Speaker, embedding: [Float])] = []
    private var nextSpeakerIndex = 1
    private var unmatchedStyle: UnmatchedSpeakerStyle = .guest

    private let config: DiarizerConfig

    init(config: DiarizerConfig = .default) {
        self.config = config
    }

    // MARK: - Lifecycle

    func prepare() async throws {
        state = .downloading
        LogManager.send("Preparing diarization models", category: .transcription)
        let models = try await DiarizerModels.downloadIfNeeded(
            to: nil,
            configuration: nil
        )
        let manager = DiarizerManager(config: config)
        manager.initialize(models: models)
        self.diarizer = manager
        self.audioConverter = AudioConverter()
        state = .ready
        LogManager.send("Diarization models ready", category: .transcription)
    }

    func startStreaming() throws {
        guard diarizer != nil else {
            throw DiarizationError.notInitialized
        }

        audioStream = try AudioStream(
            chunkDuration: 10.0,
            chunkSkip: 5.0,
            streamStartTime: 0.0,
            chunkingStrategy: .useFixedSkip,
            sampleRate: 16_000
        )

        speakerMap = [:]
        voicePrints = enrolledPrints
        nextSpeakerIndex = 1
        unmatchedStyle = .guest
        state = .processing
        LogManager.send("Diarization streaming started", category: .transcription)
    }

    func stopStreaming() {
        audioStream = nil
        state = .ready
        LogManager.send("Diarization streaming stopped", category: .transcription)
    }

    /// Process an audio buffer and return diarization segments with resolved speaker identities.
    func processBuffer(_ buffer: AVAudioPCMBuffer) throws -> [DiarizedSegment] {
        guard let diarizer, let converter = audioConverter else {
            throw DiarizationError.notInitialized
        }

        let samples = try converter.resampleBuffer(buffer)
        guard samples.count >= 48_000 else { return [] } // need ~3s minimum

        let result = try diarizer.performCompleteDiarization(
            samples,
            sampleRate: 16000
        )

        return result.segments.map { segment in
            let speaker = resolvedSpeaker(for: segment.speakerId, embedding: segment.embedding)
            return DiarizedSegment(
                speaker: speaker,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore
            )
        }
    }

    /// Process raw Float32 samples at 16kHz and return diarized segments.
    func processSamples(_ samples: [Float], atTime startTime: TimeInterval = 0) throws -> [DiarizedSegment] {
        guard let diarizer else {
            throw DiarizationError.notInitialized
        }

        guard samples.count >= 48_000 else { return [] }

        let result = try diarizer.performCompleteDiarization(
            samples,
            sampleRate: 16000,
            atTime: startTime
        )

        return result.segments.map { segment in
            let speaker = resolvedSpeaker(for: segment.speakerId, embedding: segment.embedding)
            return DiarizedSegment(
                speaker: speaker,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore
            )
        }
    }

    /// Feed audio into the streaming pipeline and get results when a chunk is complete.
    func feedAudio(_ buffer: AVAudioPCMBuffer) throws {
        try audioStream?.write(from: buffer)
    }

    // MARK: - Speaker Resolution

    /// Map internal FluidAudio speaker IDs to stable Speaker enum values.
    /// A new FluidAudio ID is first matched against known voice embeddings so
    /// the same person does not become guest-2 on the next sentence.
    private func resolvedSpeaker(for fluidSpeakerId: String, embedding: [Float] = []) -> Speaker {
        if let existing = speakerMap[fluidSpeakerId] {
            rememberVoice(existing, embedding: embedding)
            return existing
        }
        if let match = matchingKnownVoice(embedding) {
            speakerMap[fluidSpeakerId] = match
            rememberVoice(match, embedding: embedding)
            return match
        }
        let speaker = Speaker.other(unmatchedStyle.label(index: nextSpeakerIndex))
        speakerMap[fluidSpeakerId] = speaker
        nextSpeakerIndex += 1
        rememberVoice(speaker, embedding: embedding)
        return speaker
    }

    private func matchingKnownVoice(_ embedding: [Float]) -> Speaker? {
        if let match = VoicePrintMatcher.bestMatch(
            embedding: embedding,
            in: enrolledPrints.map { (item: $0.speaker, embedding: $0.embedding) },
            threshold: VoicePrintMatcher.enrolledDistance,
            margin: VoicePrintMatcher.matchMargin
        ) {
            return match.item
        }
        if let match = VoicePrintMatcher.bestMatch(
            embedding: embedding,
            in: voicePrints.map { (item: $0.speaker, embedding: $0.embedding) },
            threshold: VoicePrintMatcher.sessionDistance,
            margin: VoicePrintMatcher.matchMargin
        ) {
            return match.item
        }
        return nil
    }

    private func rememberVoice(_ speaker: Speaker, embedding: [Float]) {
        guard embedding.count >= 8 else { return }
        if let index = voicePrints.firstIndex(where: { $0.speaker.matchesIdentity(speaker) }) {
            voicePrints[index].embedding = averageEmbedding(voicePrints[index].embedding, embedding)
        } else {
            voicePrints.append((speaker, embedding))
        }
    }

    func seedEnrolledPrints(_ prints: [(speaker: Speaker, embedding: [Float])]) {
        for print in prints where print.embedding.count >= 8 {
            if let index = enrolledPrints.firstIndex(where: { $0.speaker.matchesIdentity(print.speaker) }) {
                enrolledPrints[index].embedding = print.embedding
            } else {
                enrolledPrints.append(print)
            }
            rememberVoice(print.speaker, embedding: print.embedding)
        }
    }

    func embedding(for speaker: Speaker) -> [Float]? {
        if let live = voicePrints.first(where: { $0.speaker.matchesIdentity(speaker) }) {
            return live.embedding
        }
        return enrolledPrints.first(where: { $0.speaker.matchesIdentity(speaker) })?.embedding
    }

    /// Average embeddings from a one-shot diarization pass (enrollment).
    func extractDominantEmbedding(from samples: [Float]) throws -> [Float]? {
        guard let diarizer else { throw DiarizationError.notInitialized }
        guard samples.count >= 48_000 else { return nil }
        let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16_000)
        let embeddings = result.segments.map(\.embedding).filter { $0.count >= 8 }
        guard let first = embeddings.first else { return nil }
        if embeddings.count == 1 { return first }
        var acc = first
        for extra in embeddings.dropFirst() {
            acc = averageEmbedding(acc, extra)
        }
        return acc
    }

    private func averageEmbedding(_ a: [Float], _ b: [Float]) -> [Float] {
        let n = min(a.count, b.count)
        guard n > 0 else { return b }
        return (0..<n).map { (a[$0] + b[$0]) / 2 }
    }

    /// Mark a specific FluidAudio speaker ID as "Me" (from mic channel correlation).
    func identifyAsMeSpeaker(_ fluidSpeakerId: String) {
        speakerMap[fluidSpeakerId] = Speaker.resolvedMe()
    }

    /// Keep future chunks aligned after a mid-session rename.
    func relabel(_ current: Speaker, to newSpeaker: Speaker) {
        for (id, speaker) in speakerMap {
            if speaker.matchesIdentity(current) {
                speakerMap[id] = newSpeaker
            }
        }
        for i in voicePrints.indices where voicePrints[i].speaker.matchesIdentity(current) {
            voicePrints[i].speaker = newSpeaker
        }
        for i in enrolledPrints.indices where enrolledPrints[i].speaker.matchesIdentity(current) {
            enrolledPrints[i].speaker = newSpeaker
        }
    }

    func reset() {
        speakerMap = [:]
        voicePrints = enrolledPrints
        nextSpeakerIndex = 1
        unmatchedStyle = .guest
    }

    /// One-shot pass over a whole recording. IDs are stable for the file
    /// (unlike per-chunk calls). Seeded enrolled prints are kept so a
    /// re-analyze can name people from voice stamps instead of minting
    /// a new guest/unknown for someone already on file.
    func diarizeCompleteFile(
        samples: [Float],
        unmatchedStyle: UnmatchedSpeakerStyle = .guest
    ) throws -> [DiarizedSegment] {
        guard let diarizer else { throw DiarizationError.notInitialized }
        self.unmatchedStyle = unmatchedStyle
        speakerMap = [:]
        voicePrints = enrolledPrints
        nextSpeakerIndex = 1
        guard samples.count >= 48_000 else { return [] }
        let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16_000)
        return result.segments.map { segment in
            DiarizedSegment(
                speaker: resolvedSpeaker(for: segment.speakerId, embedding: segment.embedding),
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore
            )
        }
    }

    func sessionEmbeddings() -> [(speaker: Speaker, embedding: [Float])] {
        voicePrints.filter { $0.embedding.count >= 8 }
    }

    var isReady: Bool {
        if case .ready = state { return true }
        if case .processing = state { return true }
        return false
    }
}

// MARK: - Types

struct DiarizedSegment: Sendable {
    let speaker: Speaker
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

enum UnmatchedSpeakerStyle: Sendable {
    case guest
    case unknown

    func label(index: Int) -> String {
        Speaker.placeholderLabel(index: index)
    }
}

enum DiarizationError: Error, LocalizedError {
    case notInitialized
    case modelDownloadFailed(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Diarization service not initialized. Call prepare() first."
        case .modelDownloadFailed(let reason):
            "Failed to download diarization models: \(reason)"
        case .processingFailed(let reason):
            "Diarization processing failed: \(reason)"
        }
    }
}

enum MeetingSpeakerRecovery {
    enum RecoveryError: LocalizedError {
        case noSystemAudio
        case noRemoteSegments
        case noDiarizedSpeech

        var errorDescription: String? {
            switch self {
            case .noSystemAudio:
                "No system-audio recording on disk to recover speakers from."
            case .noRemoteSegments:
                "This transcript has no remote-speaker lines to relabel."
            case .noDiarizedSpeech:
                "Diarization did not find distinct speakers in the audio."
            }
        }
    }

    /// Someone the user says was actually on the call. Embeddings come from
    /// saved voice stamps (Contacts) when they exist.
    struct ExpectedSpeaker: Identifiable, Hashable, Sendable {
        var name: String
        var speaker: Speaker
        var contactID: UUID?
        var embedding: [Float]?
        var isMe: Bool
        var isPreselected: Bool

        var id: String { (isMe ? "me:" : "p:") + name.lowercased() }

        var hasVoicePrint: Bool {
            (embedding?.count ?? 0) >= 8
        }
    }

    struct Result: Sendable {
        var changed: Int
        var unknownSpeakers: [Speaker]
        var matchedSpeakers: [Speaker]
        var embeddings: [Speaker.IdentityKey: [Float]]
    }

    /// People the re-analyze sheet can pre-select: you, attendees, named
    /// transcript voices, then other contacts that already have a stamp.
    @MainActor
    static func candidates(meeting: Meeting, contacts: [Contact]) -> [ExpectedSpeaker] {
        var list: [ExpectedSpeaker] = []

        func alreadyHas(_ speaker: Speaker, name: String) -> Bool {
            list.contains { person in
                person.speaker.matchesIdentity(speaker)
                    || SpeakerNameMatcher.samePerson(person.name, name)
            }
        }

        func append(
            name: String,
            speaker: Speaker,
            contact: Contact?,
            isMe: Bool,
            preselected: Bool
        ) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !isMe, SpeakerLinkCatalog.isPlaceholder(trimmed) { return }
            if alreadyHas(speaker, name: trimmed) { return }
            list.append(
                ExpectedSpeaker(
                    name: trimmed,
                    speaker: speaker,
                    contactID: contact?.id,
                    embedding: contact?.voicePrintEmbedding(),
                    isMe: isMe,
                    isPreselected: preselected
                )
            )
        }

        let meID = Meeting.storedMyContactID
        let meContact = contacts.first { $0.id == meID }
        let meName = SpeakerNames.effectiveMeName
            ?? meContact?.name
            ?? Speaker.defaultMeLabel
        append(
            name: meName,
            speaker: Speaker.resolvedMe(),
            contact: meContact,
            isMe: true,
            preselected: true
        )

        for attendee in meeting.attendees where attendee.id != meID {
            append(
                name: attendee.name,
                speaker: .other(attendee.name),
                contact: attendee,
                isMe: false,
                preselected: true
            )
        }

        var seenTranscript: [Speaker] = []
        for segment in meeting.segments {
            let speaker = segment.speaker
            if seenTranscript.contains(where: { $0.matchesIdentity(speaker) }) { continue }
            seenTranscript.append(speaker)
            if speaker.isMe || speaker.isGuestPlaceholder { continue }
            let contact = contacts.first { $0.matchesSpeakerName(speaker.displayName) }
            append(
                name: speaker.displayName,
                speaker: speaker,
                contact: contact,
                isMe: false,
                preselected: true
            )
        }

        for contact in contacts where !contact.isArchived && contact.hasVoicePrint {
            if contact.id == meID { continue }
            append(
                name: contact.name,
                speaker: .other(contact.name),
                contact: contact,
                isMe: false,
                preselected: false
            )
        }
        return list
    }

    /// Relabel remote transcript lines from system audio. Seeded stamps for
    /// the selected people are matched first; leftovers become unknown-N.
    @MainActor
    static func recover(
        meeting: Meeting,
        expected: [ExpectedSpeaker] = []
    ) async throws -> Result {
        let remotes = meeting.segments.filter { !$0.speaker.isMe }
        guard !remotes.isEmpty else { throw RecoveryError.noRemoteSegments }

        let audioID = meeting.audioSourceMeetingID ?? meeting.id
        let urls = AudioFileWriter.existingChunkURLs(
            base: StorageManager.shared.systemAudioURL(for: audioID)
        )
        var samples: [Float] = []
        for url in urls {
            if let chunk = try? HighQualityTranscriber.decodeFileTo16kFloatMono(url: url) {
                samples.append(contentsOf: chunk)
            }
        }
        guard !samples.isEmpty else { throw RecoveryError.noSystemAudio }

        let service = SpeakerDiarizationService()
        try await service.prepare()
        let prints = expected.compactMap { person -> (speaker: Speaker, embedding: [Float])? in
            guard let embedding = person.embedding, embedding.count >= 8 else { return nil }
            return (person.speaker, embedding)
        }
        if !prints.isEmpty {
            await service.seedEnrolledPrints(prints)
        }
        let labeled = try await service.diarizeCompleteFile(
            samples: samples,
            unmatchedStyle: .unknown
        )
        let offset = meeting.audioStartOffset
        let ranges = labeled.map {
            (
                speaker: $0.speaker,
                start: $0.startTime + offset,
                end: $0.endTime + offset
            )
        }
        guard !ranges.isEmpty else { throw RecoveryError.noDiarizedSpeech }

        var changed = 0
        var used: [Speaker] = []
        for segment in remotes {
            guard let speaker = SpeakerOverlapAssigner.speaker(
                forStart: segment.startTime,
                end: segment.endTime,
                in: ranges
            ) else { continue }
            if !used.contains(where: { $0.matchesIdentity(speaker) }) {
                used.append(speaker)
            }
            if segment.speaker != speaker {
                if segment.originalSpeakerData == nil {
                    segment.originalSpeakerData = segment.speakerData
                }
                segment.speaker = speaker
                segment.isEdited = true
                changed += 1
            }
        }

        var embeddings: [Speaker.IdentityKey: [Float]] = [:]
        for item in await service.sessionEmbeddings() {
            embeddings[item.speaker.identityKey] = item.embedding
        }

        let unknown = used.filter(\.isUnknownPlaceholder)
        let matched = used.filter { !$0.isUnknownPlaceholder }
        return Result(
            changed: changed,
            unknownSpeakers: unknown,
            matchedSpeakers: matched,
            embeddings: embeddings
        )
    }

    static func hasCollapsedRemotes(in segments: [TranscriptSegment]) -> Bool {
        let remotes = segments.filter { !$0.speaker.isMe }
        guard remotes.count >= 2 else { return false }
        let names = Set(remotes.map(\.speaker.displayName))
        if names.count >= 2 { return false }
        return remotes.contains { $0.speaker.isAnonymousRemote }
    }
}
