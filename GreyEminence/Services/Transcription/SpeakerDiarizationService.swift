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
    private var nextSpeakerIndex = 1

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
        nextSpeakerIndex = 1
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
            let speaker = resolvedSpeaker(for: segment.speakerId)
            return DiarizedSegment(
                speaker: speaker,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore,
                speakerID: segment.speakerId,
                embedding: segment.embedding
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
            let speaker = resolvedSpeaker(for: segment.speakerId)
            return DiarizedSegment(
                speaker: speaker,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore,
                speakerID: segment.speakerId,
                embedding: segment.embedding
            )
        }
    }

    /// Diarize a whole recorded track from its chunk files.
    ///
    /// Used by re-processing, which rebuilds the transcript from WhisperKit
    /// and would otherwise have no speaker information to attach to it.
    ///
    /// The timeline must match the transcriber's exactly or every attribution
    /// is shifted: chunks are walked in the same order, and a chunk that fails
    /// to decode advances the clock by zero, because that is what
    /// `HighQualityTranscriber` does with it. Audio is accumulated into
    /// windows rather than diarized per chunk — a chunk is a few seconds, too
    /// short to cluster reliably — and kept small enough to bound memory over
    /// an hour of audio.
    func diarizeTrack(
        chunkURLs: [URL],
        windowSeconds: TimeInterval = 60,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DiarizedSegment] {
        guard diarizer != nil else { throw DiarizationError.notInitialized }
        guard !chunkURLs.isEmpty else { return [] }

        speakerMap = [:]
        nextSpeakerIndex = 1

        let windowSamples = Int(windowSeconds * 16_000)
        var results: [DiarizedSegment] = []
        var window: [Float] = []
        var windowStart: TimeInterval = 0
        var clock: TimeInterval = 0

        for (index, url) in chunkURLs.enumerated() {
            try Task.checkCancellation()
            onProgress?(index, chunkURLs.count)

            // A chunk that won't decode contributes no audio, but it still
            // occupied time — and the transcriber now holds that time open
            // too. Skipping it outright would slide every later turn earlier
            // than the words it is meant to attribute.
            guard let samples = try? HighQualityTranscriber.decodeTo16kFloatMono(url: url) else {
                let assumed = HighQualityTranscriber.assumedDuration(
                    of: url,
                    fallback: HighQualityTranscriber.averageChunkDuration(elapsed: clock, completed: index)
                )
                clock += assumed
                // Close the window here: the gap means the audio either side
                // of it isn't contiguous, and clustering across it would blend
                // two different moments.
                if !window.isEmpty {
                    results.append(contentsOf: diarizeWindow(window, startingAt: windowStart))
                    window.removeAll(keepingCapacity: true)
                }
                windowStart = clock
                continue
            }

            window.append(contentsOf: samples)
            clock += TimeInterval(samples.count) / 16_000

            if window.count >= windowSamples {
                results.append(contentsOf: diarizeWindow(window, startingAt: windowStart))
                window.removeAll(keepingCapacity: true)
                windowStart = clock
            }
        }
        if !window.isEmpty {
            results.append(contentsOf: diarizeWindow(window, startingAt: windowStart))
        }
        onProgress?(chunkURLs.count, chunkURLs.count)
        return results
    }

    /// One window. A failure here loses that window's attribution, not the run
    /// — an un-attributed stretch is far better than abandoning the transcript.
    private func diarizeWindow(_ samples: [Float], startingAt offset: TimeInterval) -> [DiarizedSegment] {
        guard let diarizer, samples.count >= 48_000 else { return [] }
        do {
            let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16_000)
            return result.segments.map { segment in
                DiarizedSegment(
                    speaker: resolvedSpeaker(for: segment.speakerId),
                    startTime: offset + TimeInterval(segment.startTimeSeconds),
                    endTime: offset + TimeInterval(segment.endTimeSeconds),
                    confidence: segment.qualityScore,
                    speakerID: segment.speakerId,
                    embedding: segment.embedding
                )
            }
        } catch {
            LogManager.send(
                "Diarization failed for window at \(Int(offset))s — that stretch stays unattributed: \(error.localizedDescription)",
                category: .transcription,
                level: .warning
            )
            return []
        }
    }

    /// Feed audio into the streaming pipeline and get results when a chunk is complete.
    func feedAudio(_ buffer: AVAudioPCMBuffer) throws {
        try audioStream?.write(from: buffer)
    }

    // MARK: - Speaker Resolution

    /// Map internal FluidAudio speaker IDs to stable Speaker enum values.
    private func resolvedSpeaker(for fluidSpeakerId: String) -> Speaker {
        if let existing = speakerMap[fluidSpeakerId] {
            return existing
        }
        let speaker = Speaker.numbered(nextSpeakerIndex)
        speakerMap[fluidSpeakerId] = speaker
        nextSpeakerIndex += 1
        return speaker
    }

    /// Mark a specific FluidAudio speaker ID as "Me" (from mic channel correlation).
    func identifyAsMeSpeaker(_ fluidSpeakerId: String) {
        speakerMap[fluidSpeakerId] = .me
    }

    func reset() {
        speakerMap = [:]
        nextSpeakerIndex = 1
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
    /// The diarizer's own cluster id. Only meaningful within one run, but it
    /// is what the transcript join keys on before display labels are assigned.
    let speakerID: String
    /// Voice vector for this turn. Carried so a cluster can later be matched
    /// against an enrolled contact — the label is per-meeting, the voice is not.
    let embedding: [Float]

    init(
        speaker: Speaker,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float,
        speakerID: String = "",
        embedding: [Float] = []
    ) {
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerID = speakerID
        self.embedding = embedding
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
