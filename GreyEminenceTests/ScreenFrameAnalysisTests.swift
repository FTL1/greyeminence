import XCTest
@testable import Grey_Eminence

/// Pure tests for the vision batch selection and response parsing — no
/// network, no actor state.
final class ScreenFrameAnalysisTests: XCTestCase {

    private func snapshot(
        id: UUID = UUID(),
        session: UUID = UUID(),
        timestamp: TimeInterval,
        visualOnly: Bool = false
    ) -> ScreenFrameAnalysisService.FrameSnapshot {
        ScreenFrameAnalysisService.FrameSnapshot(
            frameID: id,
            sessionID: session,
            timestamp: timestamp,
            formattedTimestamp: "0:00",
            jpegData: Data(),
            ocrExcerpt: nil,
            isVisualOnlyChange: visualOnly
        )
    }

    // MARK: - selectBatch

    func testSelectBatchKeepsEverythingUnderLimit() {
        let frames = [snapshot(timestamp: 1), snapshot(timestamp: 2)]
        let picked = ScreenFrameAnalysisService.selectBatch(from: frames, limit: 4)
        XCTAssertEqual(picked.count, 2)
    }

    func testSelectBatchPrefersRealChanges() {
        let real = (0..<4).map { snapshot(timestamp: TimeInterval($0), visualOnly: false) }
        let video = (4..<10).map { snapshot(timestamp: TimeInterval($0), visualOnly: true) }
        let picked = ScreenFrameAnalysisService.selectBatch(from: real + video, limit: 4)
        XCTAssertEqual(picked.count, 4)
        XCTAssertTrue(picked.allSatisfy { !$0.isVisualOnlyChange })
    }

    func testSelectBatchSpacesEvenlyAcrossTimeline() {
        let frames = (0..<20).map { snapshot(timestamp: TimeInterval($0 * 10)) }
        let picked = ScreenFrameAnalysisService.selectBatch(from: frames, limit: 4)
        XCTAssertEqual(picked.count, 4)
        let times = picked.map(\.timestamp).sorted()
        XCTAssertEqual(times.first, 0)      // first frame always sampled
        XCTAssertEqual(times.last, 190)     // last frame always sampled
    }

    func testSelectBatchZeroLimitIsEmpty() {
        let frames = [snapshot(timestamp: 1)]
        XCTAssertTrue(ScreenFrameAnalysisService.selectBatch(from: frames, limit: 0).isEmpty)
    }

    // MARK: - throttleVisualOnly

    func testThrottleAlwaysPassesRealChanges() {
        let session = UUID()
        let frames = (0..<5).map { snapshot(session: session, timestamp: TimeInterval($0), visualOnly: false) }
        let result = ScreenFrameAnalysisService.throttleVisualOnly(frames, lastAnalyzedAt: [:], minimumGap: 60)
        XCTAssertEqual(result.kept.count, 5)
        XCTAssertTrue(result.droppedIDs.isEmpty)
        XCTAssertTrue(result.lastAnalyzedAt.isEmpty)
    }

    func testThrottleDropsVisualChurnWithinGap() {
        let session = UUID()
        // Video playback: one visual-only frame every 15s.
        let frames = (0..<8).map { snapshot(session: session, timestamp: TimeInterval($0 * 15), visualOnly: true) }
        let result = ScreenFrameAnalysisService.throttleVisualOnly(frames, lastAnalyzedAt: [:], minimumGap: 60)
        // t=0 passes, 15/30/45 dropped, 60 passes, 75/90 dropped, 105 dropped.
        XCTAssertEqual(result.kept.map(\.timestamp), [0, 60])
        XCTAssertEqual(result.droppedIDs.count, 6)
        XCTAssertEqual(result.lastAnalyzedAt[session], 60)
    }

    func testThrottleCarriesStateAcrossBatches() {
        let session = UUID()
        let frame = snapshot(session: session, timestamp: 70, visualOnly: true)
        let result = ScreenFrameAnalysisService.throttleVisualOnly(
            [frame], lastAnalyzedAt: [session: 30], minimumGap: 60
        )
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.droppedIDs, [frame.frameID])
        XCTAssertEqual(result.lastAnalyzedAt[session], 30)
    }

    func testThrottleIsPerSession() {
        let a = UUID(), b = UUID()
        let frames = [
            snapshot(session: a, timestamp: 10, visualOnly: true),
            snapshot(session: b, timestamp: 12, visualOnly: true),
        ]
        let result = ScreenFrameAnalysisService.throttleVisualOnly(frames, lastAnalyzedAt: [:], minimumGap: 60)
        XCTAssertEqual(result.kept.count, 2)
    }

    // MARK: - parse

    func testParseMapsIndicesToFrames() {
        let a = snapshot(timestamp: 10)
        let b = snapshot(timestamp: 20)
        let response = """
        {"frames": [
          {"index": 0, "observation": "Roadmap slide", "content_type": "slide", "key_entities": ["Q3 Roadmap"], "notable_text": null},
          {"index": 1, "observation": "Auth service diagram", "content_type": "diagram", "key_entities": ["auth-service"], "notable_text": "GA: November"}
        ]}
        """
        let parsed = ScreenFrameAnalysisService.parse(response: response, batch: [a, b], meetingID: nil)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].frameID, a.frameID)
        XCTAssertEqual(parsed[0].contentType, "slide")
        XCTAssertNil(parsed[0].notableText)
        XCTAssertEqual(parsed[1].frameID, b.frameID)
        XCTAssertEqual(parsed[1].notableText, "GA: November")
        XCTAssertEqual(parsed[1].keyEntities, ["auth-service"])
    }

    func testParseSkipsInvalidEntries() {
        let a = snapshot(timestamp: 10)
        let response = """
        {"frames": [
          {"index": 7, "observation": "out of range"},
          {"index": 0, "observation": "   "},
          {"index": 0, "observation": "Valid one"}
        ]}
        """
        let parsed = ScreenFrameAnalysisService.parse(response: response, batch: [a], meetingID: nil)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].observation, "Valid one")
        XCTAssertEqual(parsed[0].contentType, "other")  // missing → default
    }

    func testParseGarbageReturnsEmpty() {
        let parsed = ScreenFrameAnalysisService.parse(
            response: "not json at all",
            batch: [snapshot(timestamp: 1)],
            meetingID: nil
        )
        XCTAssertTrue(parsed.isEmpty)
    }
}

/// Embedding-text construction for screen frames.
final class ScreenFrameEmbeddingTests: XCTestCase {
    @MainActor
    func testObservationPlusOCR() {
        let text = EmbeddingIndexer.frameEmbeddingText(observation: "Roadmap slide", ocrText: "Q3 Roadmap\nAuth GA Nov")
        XCTAssertEqual(text, "Roadmap slide\nQ3 Roadmap\nAuth GA Nov")
    }

    @MainActor
    func testObservationOnly() {
        XCTAssertEqual(EmbeddingIndexer.frameEmbeddingText(observation: "Roadmap slide", ocrText: nil), "Roadmap slide")
    }

    @MainActor
    func testOCROnlyRequiresSubstance() {
        XCTAssertNil(EmbeddingIndexer.frameEmbeddingText(observation: nil, ocrText: "menu file"))
        XCTAssertNotNil(EmbeddingIndexer.frameEmbeddingText(observation: nil, ocrText: "A meaningful chunk of on-screen text content"))
    }

    @MainActor
    func testNothingYieldsNil() {
        XCTAssertNil(EmbeddingIndexer.frameEmbeddingText(observation: nil, ocrText: nil))
    }

    @MainActor
    func testLongOCRIsCapped() {
        let long = String(repeating: "x", count: 1000)
        let text = EmbeddingIndexer.frameEmbeddingText(observation: "obs", ocrText: long)
        XCTAssertEqual(text?.count, "obs\n".count + 300)
    }
}
