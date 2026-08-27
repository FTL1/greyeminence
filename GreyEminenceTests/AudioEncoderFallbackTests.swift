import AVFoundation
import XCTest
@testable import Grey_Eminence

/// Recording has to survive a device format the AAC encoder won't take.
/// "Audio will not be saved for this recording" is the worst outcome the app
/// has: the meeting is unrepeatable, and with no audio there is no
/// re-transcription and no diarization either.
final class AudioEncoderFallbackTests: XCTestCase {

    /// Above two channels `AVAudioFormat` needs an explicit layout — which is
    /// also why the encoder settings clamp to stereo: a multichannel aggregate
    /// carries a layout the AAC settings dictionary never supplies.
    private func format(_ rate: Double, _ channels: AVAudioChannelCount) -> AVAudioFormat {
        if channels <= 2 {
            return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        }
        let tag: AudioChannelLayoutTag = channels == 4 ? kAudioChannelLayoutTag_Quadraphonic : kAudioChannelLayoutTag_AudioUnit_5_1
        let layout = AVAudioChannelLayout(layoutTag: tag)!
        return AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
    }

    // MARK: - Choosing a fallback

    func testStandardRateIsKeptSoSpeechIsNotResampledNeedlessly() {
        XCTAssertEqual(AudioFileWriter.fallbackFormat(for: format(48000, 4)).sampleRate, 48000)
        XCTAssertEqual(AudioFileWriter.fallbackFormat(for: format(16000, 1)).sampleRate, 16000)
    }

    func testOddRateSnapsToTheNearestStandardOne() {
        // Aggregate devices report rates AAC has no bucket for.
        XCTAssertEqual(AudioFileWriter.fallbackFormat(for: format(47000, 2)).sampleRate, 48000)
        // Below the floor it clamps up rather than to an unsupported rate.
        XCTAssertEqual(AudioFileWriter.fallbackFormat(for: format(9000, 1)).sampleRate, 16000)
    }

    func testFallbackIsAlwaysMonoAndPlanar() {
        let fallback = AudioFileWriter.fallbackFormat(for: format(48000, 6))
        XCTAssertEqual(fallback.channelCount, 1)
        XCTAssertFalse(fallback.isInterleaved)
        XCTAssertEqual(fallback.commonFormat, .pcmFormatFloat32)
    }

    // MARK: - The encoder actually accepts it

    func testFallbackFormatPassesPreflight() throws {
        // The point of the fallback is that it works. If this ever fails the
        // fallback is worthless and recordings are lost.
        for rate in [8000.0, 11025, 16000, 22050, 32000, 44100, 48000, 96000] {
            let fallback = AudioFileWriter.fallbackFormat(for: format(rate, 1))
            XCTAssertNoThrow(
                try AudioFileWriter.preflightEncoder(for: fallback),
                "encoder rejected the fallback at \(rate)Hz"
            )
        }
    }

    func testOrdinaryDeviceFormatsStillPassDirectly() throws {
        // Most devices need no conversion at all; the fallback is the
        // exception, not the path.
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: format(48000, 1)))
        XCTAssertNoThrow(try AudioFileWriter.preflightEncoder(for: format(44100, 2)))
    }

    // MARK: - Settings

    func testEncoderNeverAsksForMoreThanStereo() {
        // AAC in m4a needs an explicit channel layout beyond stereo, which
        // isn't supplied — a six-channel aggregate would be refused.
        let settings = AudioFileWriter.encoderSettings(for: format(48000, 6))
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    }

    func testSampleRateIsCappedAtFortyEightKilohertz() {
        let settings = AudioFileWriter.encoderSettings(for: format(96000, 1))
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
    }

    func testFormatDescriptionNamesWhatWasRejected() {
        // The original failure said only "rejected the input format", which is
        // undiagnosable without knowing which format.
        let described = AudioFileWriter.describe(format(44100, 2))
        XCTAssertTrue(described.contains("44100"))
        XCTAssertTrue(described.contains("2ch"))
    }
}
