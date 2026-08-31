import XCTest
@testable import Grey_Eminence

final class SegmentAudioPlayerTests: XCTestCase {
    func testSlicesSpanConsecutiveFiles() {
        let a = URL(fileURLWithPath: "/tmp/a.m4a")
        let b = URL(fileURLWithPath: "/tmp/b.m4a")
        let slices = SegmentAudioPlayer.slices(
            files: [(a, 10), (b, 10)],
            from: 8,
            to: 14
        )
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].url, a)
        XCTAssertEqual(slices[0].localStart, 8, accuracy: 0.01)
        XCTAssertEqual(slices[0].duration, 2, accuracy: 0.01)
        XCTAssertEqual(slices[1].url, b)
        XCTAssertEqual(slices[1].localStart, 0, accuracy: 0.01)
        XCTAssertEqual(slices[1].duration, 4, accuracy: 0.01)
    }

    func testSliceInsideSingleFile() {
        let a = URL(fileURLWithPath: "/tmp/a.m4a")
        let slices = SegmentAudioPlayer.slices(
            files: [(a, 60)],
            from: 27,
            to: 41
        )
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].localStart, 27, accuracy: 0.01)
        XCTAssertEqual(slices[0].duration, 14, accuracy: 0.01)
    }
}
