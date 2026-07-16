import XCTest
@testable import Grey_Eminence

final class ScreenObservationFormatterTests: XCTestCase {

    private func observation(
        session: UUID,
        timestamp: TimeInterval,
        text: String,
        contentType: String = "slide",
        notable: String? = nil
    ) -> ScreenFrameAnalysisService.FrameObservation {
        ScreenFrameAnalysisService.FrameObservation(
            frameID: UUID(),
            timestamp: timestamp,
            formattedTimestamp: String(format: "%d:%02d", Int(timestamp) / 60, Int(timestamp) % 60),
            sessionID: session,
            observation: text,
            contentType: contentType,
            keyEntities: [],
            notableText: notable
        )
    }

    // MARK: - line

    func testLineFormat() {
        let line = ScreenObservationFormatter.line(
            for: observation(session: UUID(), timestamp: 754, text: "Roadmap slide", notable: "GA: Nov")
        )
        XCTAssertEqual(line, "[12:34] (slide) Roadmap slide — on screen: \"GA: Nov\"")
    }

    // MARK: - rollingBlock

    func testRollingBlockReturnsOnlyNewEntries() {
        let session = UUID()
        let all = [
            observation(session: session, timestamp: 10, text: "first"),
            observation(session: session, timestamp: 20, text: "second"),
            observation(session: session, timestamp: 30, text: "third"),
        ]
        let batch = ScreenObservationFormatter.rollingBlock(all, afterIndex: 1)
        XCTAssertNotNil(batch)
        XCTAssertEqual(batch?.endIndex, 3)
        XCTAssertFalse(batch?.block.contains("first") ?? true)
        XCTAssertTrue(batch?.block.contains("second") ?? false)
        XCTAssertTrue(batch?.block.contains("third") ?? false)
    }

    func testRollingBlockNilWhenNothingNew() {
        let all = [observation(session: UUID(), timestamp: 10, text: "only")]
        XCTAssertNil(ScreenObservationFormatter.rollingBlock(all, afterIndex: 1))
        XCTAssertNil(ScreenObservationFormatter.rollingBlock([], afterIndex: 0))
    }

    // MARK: - finalBlock

    func testFinalBlockGroupsBySessionChronologically() {
        let early = UUID(), late = UUID()
        let all = [
            observation(session: late, timestamp: 300, text: "late session"),
            observation(session: early, timestamp: 10, text: "early session"),
            observation(session: early, timestamp: 20, text: "early second"),
        ]
        let block = ScreenObservationFormatter.finalBlock(all)!
        XCTAssertTrue(block.contains("Share session 1 (0:10–0:20):"))
        XCTAssertTrue(block.contains("Share session 2 (5:00–5:00):"))
        XCTAssertLessThan(
            block.range(of: "early session")!.lowerBound,
            block.range(of: "late session")!.lowerBound
        )
    }

    func testFinalBlockDeduplicatesIdenticalObservations() {
        let session = UUID()
        let all = [
            observation(session: session, timestamp: 10, text: "same thing"),
            observation(session: session, timestamp: 20, text: "same thing"),
            observation(session: session, timestamp: 30, text: "different"),
        ]
        let block = ScreenObservationFormatter.finalBlock(all)!
        XCTAssertEqual(block.components(separatedBy: "same thing").count - 1, 1)
        XCTAssertTrue(block.contains("different"))
    }

    func testFinalBlockNilForEmpty() {
        XCTAssertNil(ScreenObservationFormatter.finalBlock([]))
    }

    func testFinalBlockRespectsCapKeepingSessionEndpoints() {
        let session = UUID()
        let all = (0..<200).map {
            observation(session: session, timestamp: TimeInterval($0 * 10), text: "observation number \($0) with some padding text to inflate size")
        }
        let block = ScreenObservationFormatter.finalBlock(all)!
        XCTAssertLessThanOrEqual(block.count, ScreenObservationFormatter.finalBlockCap + 100)
        XCTAssertTrue(block.contains("observation number 0 "))
        XCTAssertTrue(block.contains("observation number 199 "))
    }
}
