import XCTest
@testable import Grey_Eminence

/// Starting an AVAudioEngine posts a configuration-change notification of its
/// own, so an observer that rebuilds on every change feeds itself. Observed
/// 2026-08-05: five rebuilds inside one second, which burned the whole
/// recovery budget at startup and left the recording with no protection for
/// the rest of its life.
final class MicRecoveryPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func shouldRecover(
        sinceBuild: TimeInterval,
        lastBufferAgo: TimeInterval?
    ) -> Bool {
        MicrophoneCaptureService.shouldRecoverOnConfigChange(
            now: now,
            lastEngineBuildAt: now.addingTimeInterval(-sinceBuild),
            lastBufferAt: lastBufferAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    func testIgnoresChangeCausedByOurOwnEngineStart() {
        // The engine was just built; this notification is our own doing.
        XCTAssertFalse(shouldRecover(sinceBuild: 0, lastBufferAgo: nil))
        XCTAssertFalse(shouldRecover(sinceBuild: 0.2, lastBufferAgo: nil))
        XCTAssertFalse(shouldRecover(sinceBuild: 2.9, lastBufferAgo: nil))
    }

    func testIgnoresChangeWhileAudioStillFlowing() {
        // Device format changed but buffers keep arriving — rebuilding would
        // punch a needless hole in the recording.
        XCTAssertFalse(shouldRecover(sinceBuild: 60, lastBufferAgo: 0))
        XCTAssertFalse(shouldRecover(sinceBuild: 60, lastBufferAgo: 2.9))
    }

    func testRecoversWhenBuffersHaveStopped() {
        XCTAssertTrue(shouldRecover(sinceBuild: 60, lastBufferAgo: 3))
        XCTAssertTrue(shouldRecover(sinceBuild: 60, lastBufferAgo: 30))
    }

    /// The original failure: another app grabbed the device and the tap never
    /// delivered a single buffer.
    func testRecoversWhenNoBufferEverArrived() {
        XCTAssertTrue(shouldRecover(sinceBuild: 10, lastBufferAgo: nil))
    }

    func testSettleWindowBoundaryIsInclusive() {
        XCTAssertTrue(shouldRecover(sinceBuild: 3, lastBufferAgo: nil))
    }
}
