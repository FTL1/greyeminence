import XCTest
@testable import Grey_Eminence

/// Pure tests for the session-synthesis input construction, response
/// parsing, and narrative block rendering — no network, no SwiftData.
final class ShareSessionSynthesisTests: XCTestCase {

    private func frame(_ t: TimeInterval, _ text: String) -> ShareSessionSynthesisService.FrameObservationLine {
        ShareSessionSynthesisService.FrameObservationLine(
            timestamp: t,
            formattedTimestamp: String(format: "%d:%02d", Int(t) / 60, Int(t) % 60),
            observation: text
        )
    }

    private func segment(_ t: TimeInterval, _ text: String) -> SegmentSnapshot {
        SegmentSnapshot(
            speaker: .me,
            text: text,
            formattedTimestamp: String(format: "%d:%02d", Int(t) / 60, Int(t) % 60),
            isFinal: true,
            startTime: t
        )
    }

    // MARK: - makeInput

    func testMakeInputWindowsTranscriptAroundSession() {
        let input = ShareSessionSynthesisService.makeInput(
            sessionID: UUID(), meetingID: nil, windowTitle: "Deck",
            startTime: 100, endTime: 200,
            observations: [frame(100, "slide one")],
            segments: [
                segment(50, "way before"),
                segment(75, "just before"),      // inside −30s padding
                segment(150, "during"),
                segment(225, "just after"),      // inside +30s padding
                segment(300, "way after"),
            ]
        )
        XCTAssertFalse(input.transcriptExcerpt.contains("way before"))
        XCTAssertTrue(input.transcriptExcerpt.contains("just before"))
        XCTAssertTrue(input.transcriptExcerpt.contains("during"))
        XCTAssertTrue(input.transcriptExcerpt.contains("just after"))
        XCTAssertFalse(input.transcriptExcerpt.contains("way after"))
    }

    func testMakeInputCapsFrameLines() {
        let long = String(repeating: "x", count: 2_000)
        let input = ShareSessionSynthesisService.makeInput(
            sessionID: UUID(), meetingID: nil, windowTitle: nil,
            startTime: 0, endTime: 10,
            observations: [frame(0, long)],
            segments: []
        )
        // 900-char cap + timestamp prefix + ellipsis.
        XCTAssertLessThan(input.frameDescriptions.count, 950)
        XCTAssertTrue(input.frameDescriptions.contains("…"))
    }

    func testMakeInputMiddleDropsKeepsFirstAndLast() {
        let observations = (0..<60).map { frame(TimeInterval($0 * 10), "frame \($0) " + String(repeating: "pad ", count: 150)) }
        let input = ShareSessionSynthesisService.makeInput(
            sessionID: UUID(), meetingID: nil, windowTitle: nil,
            startTime: 0, endTime: 600,
            observations: observations,
            segments: []
        )
        XCTAssertLessThanOrEqual(input.frameDescriptions.count, ShareSessionSynthesisService.frameBlockCap + 200)
        XCTAssertTrue(input.frameDescriptions.contains("frame 0 "))
        XCTAssertTrue(input.frameDescriptions.contains("frame 59 "))
        XCTAssertTrue(input.frameDescriptions.contains("omitted for length"))
    }

    func testMakeInputCapsTranscript() {
        let segments = (0..<200).map { segment(TimeInterval($0), "line \($0) " + String(repeating: "word ", count: 30)) }
        let input = ShareSessionSynthesisService.makeInput(
            sessionID: UUID(), meetingID: nil, windowTitle: nil,
            startTime: 0, endTime: 200,
            observations: [frame(0, "obs")],
            segments: segments
        )
        XCTAssertLessThanOrEqual(input.transcriptExcerpt.count, ShareSessionSynthesisService.transcriptCap + 100)
        XCTAssertTrue(input.transcriptExcerpt.contains("transcript trimmed"))
        XCTAssertTrue(input.transcriptExcerpt.contains("line 0 "))
        XCTAssertTrue(input.transcriptExcerpt.contains("line 199 "))
    }

    func testMakeInputEmptyTranscriptGetsPlaceholder() {
        let input = ShareSessionSynthesisService.makeInput(
            sessionID: UUID(), meetingID: nil, windowTitle: nil,
            startTime: 0, endTime: 10,
            observations: [frame(0, "obs")],
            segments: []
        )
        XCTAssertTrue(input.transcriptExcerpt.contains("no speech captured"))
    }

    // MARK: - parse

    func testParseFullResponse() {
        let sessionID = UUID()
        let response = """
        {
          "narrative": "The team walked through the Q3 roadmap deck.",
          "key_moments": [
            {"time": "12:34", "label": "Roadmap slide shown"},
            {"time": "1:05:00", "label": "Budget table debated"},
            {"time": "0:10", "label": "Deck opened"}
          ],
          "entities": ["Q3 Roadmap", "auth-service"]
        }
        """
        let parsed = ShareSessionSynthesisService.parse(response: response, sessionID: sessionID, modelIdentifier: "m")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.sessionID, sessionID)
        XCTAssertEqual(parsed?.narrative, "The team walked through the Q3 roadmap deck.")
        // Sorted chronologically, h:mm:ss handled.
        XCTAssertEqual(parsed?.keyMoments.map(\.timestamp), [10, 754, 3900])
        XCTAssertEqual(parsed?.entities, ["Q3 Roadmap", "auth-service"])
    }

    func testParseDropsMomentsWithoutUsableTime() {
        let response = """
        {"narrative": "n", "key_moments": [{"time": "later", "label": "vague"}, {"time": "0:05", "label": "real"}]}
        """
        let parsed = ShareSessionSynthesisService.parse(response: response, sessionID: UUID(), modelIdentifier: "m")
        XCTAssertEqual(parsed?.keyMoments.count, 1)
        XCTAssertEqual(parsed?.keyMoments.first?.label, "real")
    }

    func testParseRejectsEmptyNarrative() {
        XCTAssertNil(ShareSessionSynthesisService.parse(response: "{\"narrative\": \"  \"}", sessionID: UUID(), modelIdentifier: "m"))
        XCTAssertNil(ShareSessionSynthesisService.parse(response: "garbage", sessionID: UUID(), modelIdentifier: "m"))
    }

    func testParseTimestampVariants() {
        XCTAssertEqual(ShareSessionSynthesisService.parseTimestamp("12:34"), 754)
        XCTAssertEqual(ShareSessionSynthesisService.parseTimestamp("[3:05]"), 185)
        XCTAssertEqual(ShareSessionSynthesisService.parseTimestamp("1:02:03"), 3723)
        XCTAssertNil(ShareSessionSynthesisService.parseTimestamp("noon"))
        XCTAssertNil(ShareSessionSynthesisService.parseTimestamp(""))
    }

    // MARK: - Narrative final block

    private func observation(session: UUID, timestamp: TimeInterval, text: String) -> ScreenObservationFormatter.Observation {
        ScreenObservationFormatter.Observation(
            frameID: UUID(),
            timestamp: timestamp,
            formattedTimestamp: String(format: "%d:%02d", Int(timestamp) / 60, Int(timestamp) % 60),
            sessionID: session,
            observation: text,
            contentType: "slide",
            keyEntities: [],
            notableText: nil
        )
    }

    func testFinalBlockRendersNarrativesWithKeyMoments() {
        let block = ScreenObservationFormatter.finalBlock(
            narratives: [
                ScreenObservationFormatter.NarrativeSnapshot(
                    windowTitle: "Q3 Deck",
                    startTime: 720,
                    endTime: 1110,
                    narrative: "The roadmap discussion.",
                    keyMoments: [ShareSessionSummary.KeyMoment(timestamp: 754, label: "Roadmap slide")]
                ),
            ],
            fallbackFrames: []
        )
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Share session 1 — \"Q3 Deck\" (12:00–18:30):"))
        XCTAssertTrue(block!.contains("The roadmap discussion."))
        XCTAssertTrue(block!.contains("Key moments: [12:34] Roadmap slide"))
    }

    func testFinalBlockMixesNarrativesAndFallbackFrames() {
        let fallbackSession = UUID()
        let block = ScreenObservationFormatter.finalBlock(
            narratives: [
                ScreenObservationFormatter.NarrativeSnapshot(
                    windowTitle: nil, startTime: 0, endTime: 60,
                    narrative: "First share recap.", keyMoments: []
                ),
            ],
            fallbackFrames: [observation(session: fallbackSession, timestamp: 120, text: "orphan frame")]
        )
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("First share recap."))
        XCTAssertTrue(block!.contains("without a recap"))
        XCTAssertTrue(block!.contains("orphan frame"))
    }

    func testFinalBlockNoNarrativesFallsBackToFrames() {
        let session = UUID()
        let block = ScreenObservationFormatter.finalBlock(
            narratives: [],
            fallbackFrames: [observation(session: session, timestamp: 10, text: "plain frames")]
        )
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("plain frames"))
        XCTAssertFalse(block!.contains("recap"))
    }

    func testFinalBlockOrdersNarrativesChronologically() {
        let block = ScreenObservationFormatter.finalBlock(
            narratives: [
                ScreenObservationFormatter.NarrativeSnapshot(windowTitle: nil, startTime: 600, endTime: 700, narrative: "Later share.", keyMoments: []),
                ScreenObservationFormatter.NarrativeSnapshot(windowTitle: nil, startTime: 10, endTime: 60, narrative: "Earlier share.", keyMoments: []),
            ],
            fallbackFrames: []
        )!
        XCTAssertLessThan(
            block.range(of: "Earlier share.")!.lowerBound,
            block.range(of: "Later share.")!.lowerBound
        )
        XCTAssertTrue(block.contains("Share session 1"))
        XCTAssertTrue(block.contains("Share session 2"))
    }

    func testFinalBlockStaysUnderCap() {
        let narratives = (0..<10).map { i in
            ScreenObservationFormatter.NarrativeSnapshot(
                windowTitle: "W\(i)", startTime: TimeInterval(i * 100), endTime: TimeInterval(i * 100 + 50),
                narrative: String(repeating: "n", count: 900), keyMoments: []
            )
        }
        let session = UUID()
        let fallback = (0..<50).map { observation(session: session, timestamp: TimeInterval($0), text: "frame \($0)") }
        let block = ScreenObservationFormatter.finalBlock(narratives: narratives, fallbackFrames: fallback)!
        XCTAssertLessThanOrEqual(block.count, ScreenObservationFormatter.finalBlockCap)
    }
}
