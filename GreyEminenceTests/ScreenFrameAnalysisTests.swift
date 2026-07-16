import XCTest
@testable import Grey_Eminence

/// Pure tests for the vision batch selection and response parsing — no
/// network, no actor state.
final class ScreenFrameAnalysisTests: XCTestCase {

    private func snapshot(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        visualOnly: Bool = false
    ) -> ScreenFrameAnalysisService.FrameSnapshot {
        ScreenFrameAnalysisService.FrameSnapshot(
            frameID: id,
            sessionID: UUID(),
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
