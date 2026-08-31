import XCTest
@testable import Grey_Eminence

final class CaptureSafetyPolicyTests: XCTestCase {
    func testFourHourRecordingCap() {
        XCTAssertEqual(
            CaptureSafetyPolicy.shouldAutoStopRecording(
                elapsed: 4 * 3600,
                autoDetected: false,
                secondsSinceSpeech: 10
            ),
            .maxDuration
        )
        XCTAssertNil(
            CaptureSafetyPolicy.shouldAutoStopRecording(
                elapsed: 3 * 3600,
                autoDetected: false,
                secondsSinceSpeech: 10
            )
        )
    }

    func testIdleSpeechStopsAutoRecordingsOnly() {
        XCTAssertEqual(
            CaptureSafetyPolicy.shouldAutoStopRecording(
                elapsed: 25 * 60,
                autoDetected: true,
                secondsSinceSpeech: 20 * 60
            ),
            .idleSpeech
        )
        XCTAssertNil(
            CaptureSafetyPolicy.shouldAutoStopRecording(
                elapsed: 25 * 60,
                autoDetected: false,
                secondsSinceSpeech: 20 * 60
            )
        )
    }

    func testLiveAIFollowsTheToggleNotTheClock() {
        XCTAssertFalse(CaptureSafetyPolicy.shouldStopLiveAI(liveEnabled: true))
        XCTAssertTrue(CaptureSafetyPolicy.shouldStopLiveAI(liveEnabled: false))
    }
}
