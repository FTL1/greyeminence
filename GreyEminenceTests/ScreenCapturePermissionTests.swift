import XCTest
@testable import Grey_Eminence

final class ScreenCapturePermissionTests: XCTestCase {
    func testDoesNotLatchWhenPreflightGranted() {
        let error = NSError(
            domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
            code: -3801,
            userInfo: [NSLocalizedDescriptionKey: "The user declined the screen capture prompt"]
        )
        XCTAssertFalse(
            ScreenCapturePermission.shouldLatchDenial(
                preflightGranted: true,
                consecutiveFailures: 6,
                error: error
            )
        )
    }

    func testLatchesAfterRepeatedTCCFailuresWhenPreflightDenied() {
        let error = NSError(
            domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
            code: -3801,
            userInfo: [NSLocalizedDescriptionKey: "The user declined the screen capture prompt"]
        )
        XCTAssertFalse(
            ScreenCapturePermission.shouldLatchDenial(
                preflightGranted: false,
                consecutiveFailures: 1,
                error: error
            )
        )
        XCTAssertTrue(
            ScreenCapturePermission.shouldLatchDenial(
                preflightGranted: false,
                consecutiveFailures: 2,
                error: error
            )
        )
    }

    func testTransientNonTCCNeedsMoreFailures() {
        let error = NSError(
            domain: "NSPOSIXErrorDomain",
            code: 60,
            userInfo: [NSLocalizedDescriptionKey: "Operation timed out"]
        )
        XCTAssertFalse(
            ScreenCapturePermission.shouldLatchDenial(
                preflightGranted: false,
                consecutiveFailures: 2,
                error: error
            )
        )
        XCTAssertTrue(
            ScreenCapturePermission.shouldLatchDenial(
                preflightGranted: false,
                consecutiveFailures: 4,
                error: error
            )
        )
    }

    func testLikelyTCCFromUserDeclinedCode() {
        let error = NSError(
            domain: "SCStreamErrorDomain",
            code: -3801,
            userInfo: [NSLocalizedDescriptionKey: "failed"]
        )
        XCTAssertTrue(ScreenCapturePermission.isLikelyTCCDenial(error))
    }
}