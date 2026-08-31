import XCTest
@preconcurrency import AVFoundation
@testable import Grey_Eminence

/// Real-AVAudioFile tests for the encoder settings matrix. These are the
/// regression guard for the v0.9.45 incident, where 32 kbps stereo at 48 kHz
/// was below AAC-LC's per-channel floor and every chunk produced by the
/// encoder was corrupt. Any combination tested here must: (a) preflight
/// without throwing, (b) produce a file that AVAudioFile can re-open for
/// reading.
final class AudioFileWriterEncoderTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileWriterEncoderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    private func makeFormat(sampleRate: Double, channels: AVAudioChannelCount) throws -> AVAudioFormat {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )
        return try XCTUnwrap(format, "Could not build PCM float32 format at \(sampleRate)Hz × \(channels)ch")
    }

    // MARK: - Preflight

    func test_preflight_mono_44100_passes() throws {
        let fmt = try makeFormat(sampleRate: 44100, channels: 1)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_preflight_mono_48000_passes() throws {
        let fmt = try makeFormat(sampleRate: 48000, channels: 1)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_preflight_stereo_44100_passes() throws {
        let fmt = try makeFormat(sampleRate: 44100, channels: 2)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_preflight_stereo_48000_passes() throws {
        // This is the exact case that broke in v0.9.45–0.9.47.
        let fmt = try makeFormat(sampleRate: 48000, channels: 2)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_preflight_stereo_96000_passes() throws {
        let fmt = try makeFormat(sampleRate: 96000, channels: 2)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_preflight_interleaved_mono_48000_passes() throws {
        let fmt = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        ))
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
        let writeable = AudioFileWriter.writeableFormat(from: fmt)
        XCTAssertFalse(writeable.isInterleaved)
        XCTAssertEqual(writeable.channelCount, 1)
        XCTAssertEqual(writeable.commonFormat, .pcmFormatFloat32)
    }

    func test_writeableFormat_clamps_aggregate_channel_count() throws {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 4,
            interleaved: false
        ) else {
            throw XCTSkip("4-channel PCM is not available on this host")
        }
        let writeable = AudioFileWriter.writeableFormat(from: fmt)
        XCTAssertLessThanOrEqual(writeable.channelCount, 2)
        XCTAssertFalse(writeable.isInterleaved)
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: fmt))
    }

    func test_start_and_write_interleaved_mono() async throws {
        let base = tempDir.appendingPathComponent("mic-agg.m4a")
        let writer = AudioFileWriter(outputURL: base)
        let fmt = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        ))
        try await writer.start(inputFormat: fmt)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4800))
        buffer.frameLength = 4800
        try await writer.write(buffer)
        await writer.stop()
        let chunks = AudioFileWriter.existingChunkURLs(base: base)
        XCTAssertEqual(chunks.count, 1)
        let readable = try AVAudioFile(forReading: try XCTUnwrap(chunks.first))
        XCTAssertGreaterThan(readable.length, 0)
    }

    // MARK: - End-to-end: write, checkpoint, verify readable

    func test_write_and_reopen_stereo_48000() async throws {
        let base = tempDir.appendingPathComponent("sys.m4a")
        let writer = AudioFileWriter(outputURL: base)
        let fmt = try makeFormat(sampleRate: 48000, channels: 2)

        try await writer.start(inputFormat: fmt)

        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16000),
            "Could not allocate probe buffer"
        )
        buffer.frameLength = 16000
        try await writer.write(buffer)

        try await writer.checkpoint()
        try await writer.write(buffer)
        await writer.stop()

        let chunks = AudioFileWriter.existingChunkURLs(base: base)
        XCTAssertEqual(chunks.count, 2, "Expected two chunks after one checkpoint")
        for chunk in chunks {
            let readable = try AVAudioFile(forReading: chunk)
            XCTAssertGreaterThan(readable.length, 0, "Chunk \(chunk.lastPathComponent) has zero length — encoder rejected the settings")
        }
    }

    func test_write_and_reopen_mono_44100() async throws {
        let base = tempDir.appendingPathComponent("mic.m4a")
        let writer = AudioFileWriter(outputURL: base)
        let fmt = try makeFormat(sampleRate: 44100, channels: 1)

        try await writer.start(inputFormat: fmt)

        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 8000),
            "Could not allocate probe buffer"
        )
        buffer.frameLength = 8000
        try await writer.write(buffer)
        await writer.stop()

        let chunks = AudioFileWriter.existingChunkURLs(base: base)
        XCTAssertEqual(chunks.count, 1)
        let readable = try AVAudioFile(forReading: try XCTUnwrap(chunks.first))
        XCTAssertGreaterThan(readable.length, 0)
    }

    // MARK: - Failure counter

    func test_write_converts_stereo_into_mono_writer() async throws {
        let base = tempDir.appendingPathComponent("mic.m4a")
        let writer = AudioFileWriter(outputURL: base)
        let fmt = try makeFormat(sampleRate: 48000, channels: 1)
        try await writer.start(inputFormat: fmt)

        let stereo = try makeFormat(sampleRate: 48000, channels: 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 1024))
        buffer.frameLength = 1024
        try await writer.write(buffer)

        let consecutive = await writer.consecutiveWriteFailures
        XCTAssertEqual(consecutive, 0)
        await writer.stop()
        let chunks = AudioFileWriter.existingChunkURLs(base: base)
        XCTAssertEqual(chunks.count, 1)
    }
}
