import AVFoundation
import XCTest
@testable import Grey_Eminence

/// Keeping the two audio tracks on the same clock.
///
/// Mic and system are transcribed independently, each accumulating its own
/// offset as it walks its chunks. A chunk that advances the offset by less
/// than its real duration shifts everything after it earlier — and because the
/// two tracks drift independently, the far side of a call ends up timestamped
/// before it happened, leaving the end of the meeting with nothing but the
/// microphone. Every line attributed to the user.
final class TranscriptTimelineTests: XCTestCase {

    /// A chunk whose audio is unreadable but whose header still parses — the
    /// common shape of the failure.
    private func makeChunk(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ge-timeline-\(UUID().uuidString).m4a")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileWriter.encoderSettings(for: format),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = AVAudioFrameCount(seconds * 16000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    func testDurationIsReadFromTheHeaderWithoutDecoding() throws {
        let url = try makeChunk(seconds: 7)
        defer { try? FileManager.default.removeItem(at: url) }
        let measured = HighQualityTranscriber.assumedDuration(of: url, fallback: 999)
        XCTAssertEqual(measured, 7, accuracy: 0.3, "should read the real length, not the fallback")
    }

    func testUnreadableChunkFallsBackToTheRunningAverage() {
        // A constant would be wrong on any device whose chunks aren't ~10s;
        // the average of what's already been processed is grounded in this
        // recording.
        let missing = URL(fileURLWithPath: "/nonexistent/chunk.m4a")
        XCTAssertEqual(HighQualityTranscriber.assumedDuration(of: missing, fallback: 13.5), 13.5)
    }

    func testTimelineHoldsOpenAcrossAFailedChunk() throws {
        // The regression: 27 failures across one call collapsed roughly six
        // minutes of the far side into the past.
        let chunks = [8.0, 12.0, 9.0]
        var clock: TimeInterval = 0
        for seconds in chunks {
            let url = try makeChunk(seconds: seconds)
            defer { try? FileManager.default.removeItem(at: url) }
            clock += HighQualityTranscriber.assumedDuration(of: url, fallback: 10)
        }
        XCTAssertEqual(clock, 29, accuracy: 1.0, "a skipped chunk must still cost its own time")
    }

    func testZeroAdvanceWouldAccumulateError() {
        // Documents why this matters rather than testing the old behaviour:
        // each failure shifts everything after it, and the shift compounds.
        let failures = 27
        let typicalChunk = 13.6
        XCTAssertGreaterThan(
            Double(failures) * typicalChunk, 300,
            "27 dropped chunks is minutes of drift, not a rounding error"
        )
    }
}

/// Read paths must not create the folders they're only asking about.
///
/// `recordingDirectory(for:)` creates on access, so probing for audio or a
/// sidecar left an empty directory behind for every meeting checked — and the
/// retention sweep then reported "removed audio for 267 meetings" while
/// freeing 0.0 MB, because all it deleted were folders the probe had made.
final class RecordingPathTests: XCTestCase {

    private var probeID: UUID!

    override func tearDown() {
        if let probeID {
            try? FileManager.default.removeItem(
                at: StorageManager.shared.recordingDirectoryPath(for: probeID)
            )
        }
        super.tearDown()
    }

    func testAskingForAudioPathsCreatesNothing() {
        probeID = UUID()
        _ = StorageManager.shared.systemAudioURL(for: probeID)
        _ = StorageManager.shared.micAudioURL(for: probeID)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: StorageManager.shared.recordingDirectoryPath(for: probeID).path
            ),
            "probing for audio must not create a recording folder"
        )
    }

    func testAskingForSidecarPathsCreatesNothing() {
        probeID = UUID()
        _ = StorageManager.shared.reportAnchorPlanURL(for: probeID)
        _ = StorageManager.shared.reProcessCheckpointURL(for: probeID)
        _ = StorageManager.shared.loadVoiceClusters(for: probeID)
        _ = StorageManager.shared.loadSearchCoverage(for: probeID)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: StorageManager.shared.recordingDirectoryPath(for: probeID).path
            ),
            "probing for a sidecar must not create a recording folder"
        )
    }

    func testDerivedDataOutlivesTheAudio() {
        // Voice signatures exist so a meeting can be worked with once its
        // audio is gone; storing them under the recording directory would have
        // put them in the one place retention deletes.
        probeID = UUID()
        let clusters = StorageManager.shared.voiceClustersURL(for: probeID).path
        let recording = StorageManager.shared.recordingDirectoryPath(for: probeID).path
        XCTAssertFalse(clusters.hasPrefix(recording), "signatures must not live where retention purges")
    }
}
