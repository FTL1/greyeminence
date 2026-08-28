import SwiftData
import XCTest
@testable import Grey_Eminence

/// Background work has to be both visible and interruptible.
///
/// Startup maintenance was already named in the status bar while it ran — and
/// the window was frozen solid for the duration, which is worse than silence:
/// it looks like the app is working when it is unusable.
@MainActor
final class StartupActivityTests: XCTestCase {

    func testMaintenanceReportsEveryStepItRuns() async {
        let container = try! ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        var steps: [(Int, Int, String)] = []
        _ = await MaintenanceService.runStartupMaintenance(
            modelContext: ModelContext(container),
            force: true
        ) { done, total, name in steps.append((done, total, name)) }

        XCTAssertFalse(steps.isEmpty, "a long job that reports nothing is indistinguishable from a hung one")
        XCTAssertEqual(steps.last?.0, steps.last?.1, "the last report should show completion")
        XCTAssertTrue(steps.dropLast().allSatisfy { !$0.2.isEmpty }, "every step should name itself")
        XCTAssertTrue(
            steps.map(\.0) == steps.map(\.0).sorted(),
            "progress must never go backwards"
        )
    }

    func testThrottledRunReportsNothingAndDoesNoWork() async {
        // The common launch: maintenance ran recently, so nothing should be
        // shown at all rather than a bar that flashes and vanishes.
        let container = try! ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        _ = await MaintenanceService.runStartupMaintenance(modelContext: context, force: true)

        var steps = 0
        let report = await MaintenanceService.runStartupMaintenance(modelContext: context) { _, _, _ in steps += 1 }
        XCTAssertTrue(report.skipped)
        XCTAssertEqual(steps, 0)
    }

    // MARK: - Status bar

    func testRetitlingKeepsTheSameActivity() {
        // The bar's appear/disappear animation keys on identity; a step
        // change must not read as a new activity starting.
        let coordinator = TransientActivityCoordinator.shared
        let before = TransientActivityCoordinator.Activity(
            label: "Startup maintenance",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        var after = before
        after.label = "Startup maintenance — trimming the usage log"
        XCTAssertEqual(before, after, "retitling must preserve identity")
        XCTAssertNil(coordinator.current, "no activity should be running in a test")
    }
}
