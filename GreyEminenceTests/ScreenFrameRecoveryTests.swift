import XCTest
@testable import Grey_Eminence

/// Pure helpers of the frame-row recovery (rebuilding rows from on-disk
/// images after a schema-downgrade wipe).
final class ScreenFrameRecoveryTests: XCTestCase {

    func testSequenceFromFilename() {
        XCTAssertEqual(ScreenFrameRecoveryService.sequence(fromFilename: "000042.jpg"), 42)
        XCTAssertEqual(ScreenFrameRecoveryService.sequence(fromFilename: "000000.jpg"), 0)
        XCTAssertEqual(ScreenFrameRecoveryService.sequence(fromFilename: "not-a-frame.jpg"), 0)
    }

    func testElapsedClampsToMeetingBounds() {
        let start = Date(timeIntervalSince1970: 1_000)
        // Normal case: 90s into a one-hour meeting.
        XCTAssertEqual(
            ScreenFrameRecoveryService.elapsed(capturedAt: start.addingTimeInterval(90), meetingStart: start, duration: 3600),
            90
        )
        // Before start (clock skew) clamps to 0.
        XCTAssertEqual(
            ScreenFrameRecoveryService.elapsed(capturedAt: start.addingTimeInterval(-5), meetingStart: start, duration: 3600),
            0
        )
        // Past the end clamps to duration.
        XCTAssertEqual(
            ScreenFrameRecoveryService.elapsed(capturedAt: start.addingTimeInterval(4000), meetingStart: start, duration: 3600),
            3600
        )
        // Zero-duration meeting (interrupted rows) never clamps upward.
        XCTAssertEqual(
            ScreenFrameRecoveryService.elapsed(capturedAt: start.addingTimeInterval(120), meetingStart: start, duration: 0),
            120
        )
    }
}
