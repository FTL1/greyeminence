import XCTest
@testable import Grey_Eminence

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceIsEmpty() {
        XCTAssertEqual(AudioLevelMeter.litSegments(rms: 0, count: 20), 0)
        XCTAssertEqual(AudioLevelMeter.fill(rms: 0), 0, accuracy: 0.001)
    }

    func testSpeechLightsSeveralBars() {
        // RMS 0.02 ≈ −34 dBFS → well above −50, below −8.
        let lit = AudioLevelMeter.litSegments(rms: 0.02, count: 20)
        XCTAssertGreaterThanOrEqual(lit, 6)
        XCTAssertLessThan(lit, 20)
    }

    func testLinearScaleWouldStickOnFirstBar() {
        // The Settings meter used `i/20 < rms`. Speech at 0.03 lights one LED.
        let rms: Float = 0.03
        var linearLit = 0
        for i in 0..<20 where Double(i) / 20.0 < Double(rms) {
            linearLit += 1
        }
        XCTAssertEqual(linearLit, 1)
        XCTAssertGreaterThan(AudioLevelMeter.litSegments(rms: rms, count: 20), 5)
    }

    func testHotSignalFillsTheMeter() {
        XCTAssertEqual(AudioLevelMeter.litSegments(rms: 0.5, count: 20), 20)
        XCTAssertEqual(AudioLevelMeter.fill(rms: 1), 1, accuracy: 0.001)
    }

    func testDBFSOfUnityIsZero() {
        XCTAssertEqual(AudioLevelMeter.dBFS(rms: 1), 0, accuracy: 0.01)
    }
}
