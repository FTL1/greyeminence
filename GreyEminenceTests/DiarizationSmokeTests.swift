import XCTest
@testable import Grey_Eminence

/// A diagnostic, not a unit test: runs the real diarizer over real recorded
/// audio and reports what it heard.
///
/// The alignment logic is covered by `SpeakerAlignmentTests`; what that can't
/// tell you is whether FluidAudio actually separates voices on a Teams call at
/// the window size the repair uses. Skips cleanly when the audio isn't there,
/// so CI and other machines are unaffected.
final class DiarizationSmokeTests: XCTestCase {

    /// Which meeting to diarize, read from a file inside the app container:
    ///   …/Application Support/GreyEminence/diarize-target.txt
    ///
    /// Not an environment variable (xcodebuild doesn't forward the shell's)
    /// and not a default (a sandboxed host reads preferences from its own
    /// container, not the domain `defaults write` targets). Missing means
    /// skip — this costs minutes and needs recordings only a dev machine has.
    private var meetingID: String {
        let url = StorageManager.shared.appSupportURL.appendingPathComponent("diarize-target.txt")
        return ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testDiarizeRealMeetingAudio() async throws {
        try XCTSkipIf(meetingID.isEmpty, "Write a meeting UUID to diarize-target.txt in the app container to run.")

        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.greyeminence.app/Data/Library/Application Support/GreyEminence/Recordings")
            .appendingPathComponent(meetingID)
        let chunks = AudioFileWriter.existingChunkURLs(base: dir.appendingPathComponent("system.m4a"))
        try XCTSkipIf(chunks.isEmpty, "No system audio for \(meetingID).")

        let service = SpeakerDiarizationService()
        try await service.prepare()

        let started = Date()
        let segments = try await service.diarizeTrack(chunkURLs: chunks)
        let elapsed = Date().timeIntervalSince(started)

        let spans = segments.map {
            SpeakerAlignment.Span(speakerID: $0.speakerID, start: $0.startTime, end: $0.endTime)
        }
        let significant = SpeakerAlignment.significantSpeakerIDs(in: spans)
        var talkTime: [String: TimeInterval] = [:]
        for span in spans { talkTime[span.speakerID, default: 0] += span.duration }
        let covered = spans.reduce(0) { $0 + $1.duration }
        let span = (spans.map(\.end).max() ?? 0) - (spans.map(\.start).min() ?? 0)

        print("""

        ── diarization: \(meetingID) ──
        chunks:        \(chunks.count)
        wall clock:    \(String(format: "%.1f", elapsed))s
        turns:         \(segments.count)
        raw clusters:  \(talkTime.count)
        significant:   \(significant.count)  (>= 3s of speech)
        audio spanned: \(String(format: "%.0f", span))s, attributed \(String(format: "%.0f", covered))s
        talk time:
        \(talkTime.sorted { $0.value > $1.value }
            .map { "  \($0.key.prefix(12).padding(toLength: 12, withPad: " ", startingAt: 0))  \(String(format: "%6.1f", $0.value))s\(significant.contains($0.key) ? "" : "   (sliver)")" }
            .joined(separator: "\n"))

        """)

        XCTAssertFalse(segments.isEmpty, "diarizer produced no turns at all")
        // Embeddings are what cross-meeting voice matching will key on, so
        // confirm they're actually coming through before building on them.
        XCTAssertFalse(segments.first?.embedding.isEmpty ?? true, "no voice embedding on the turns")
    }
}
