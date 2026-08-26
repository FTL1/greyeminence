import XCTest
@testable import Grey_Eminence

/// The footer bar's progress readout. A long backfill with only a spinner
/// reads as a hang, so the countable case has to render — and the
/// indeterminate case has to keep working, because most transient work
/// genuinely has no total.
@MainActor
final class TransientActivityProgressTests: XCTestCase {

    private typealias Progress = TransientActivityCoordinator.Progress

    func testFractionIsCompletedOverTotal() {
        XCTAssertEqual(Progress(completed: 105, total: 420).fraction, 0.25, accuracy: 0.0001)
    }

    func testFractionIsZeroBeforeAnythingCompletes() {
        XCTAssertEqual(Progress(completed: 0, total: 420).fraction, 0)
    }

    func testFractionNeverExceedsOne() {
        // A late tick after the loop finishes must not overdraw the bar.
        XCTAssertEqual(Progress(completed: 421, total: 420).fraction, 1)
    }

    func testZeroTotalDoesNotDivideByZero() {
        XCTAssertEqual(Progress(completed: 0, total: 0).fraction, 0)
    }

    func testActivityEqualityIgnoresProgress() {
        // Equality drives the bar's appear/disappear animation. If progress
        // counted, every tick would re-animate the whole bar.
        let base = TransientActivityCoordinator.Activity(
            label: "Indexing meetings for search…",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        var advanced = base
        advanced.progress = Progress(completed: 200, total: 420)
        XCTAssertEqual(base, advanced)
    }

    func testProgressForNothingRunningIsIgnored() {
        // A tick arriving after the activity ended must not resurrect the bar.
        let coordinator = TransientActivityCoordinator.shared
        XCTAssertNil(coordinator.current)
        coordinator.setProgress(completed: 5, total: 10)
        XCTAssertNil(coordinator.current)
    }
}
