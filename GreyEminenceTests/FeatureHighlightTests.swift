import XCTest
@testable import Grey_Eminence

/// Version comparison and the "what to show after an update" filter behind the
/// What's New sheet. Assertions are written as *properties* (not exact catalog
/// counts) so they don't go stale as highlights are added over time.
final class FeatureHighlightTests: XCTestCase {

    // MARK: SemVer

    func testSemVerOrdering() {
        XCTAssertEqual(SemVer.compare("0.23.13", "0.23.12"), .orderedDescending)
        XCTAssertEqual(SemVer.compare("0.23.12", "0.23.13"), .orderedAscending)
        XCTAssertEqual(SemVer.compare("0.23.13", "0.23.13"), .orderedSame)
        // Missing components read as zero.
        XCTAssertEqual(SemVer.compare("0.24", "0.24.0"), .orderedSame)
        XCTAssertEqual(SemVer.compare("0.24", "0.23.9"), .orderedDescending)
        // Numeric, not lexicographic: 9 < 13.
        XCTAssertEqual(SemVer.compare("0.9.2", "0.23.0"), .orderedAscending)
        // Leading "v" and trailing tags are ignored.
        XCTAssertEqual(SemVer.compare("v0.23.13", "0.23.13-beta"), .orderedSame)
        // Grey Conseil suffixes compare by the numeric tail: ftl18 > ftl17.
        XCTAssertEqual(SemVer.compare("0.28.4-ftl18", "0.28.4-ftl17"), .orderedDescending)
    }

    // MARK: Pending highlights

    func testNothingPendingAtOrAboveNewestVersion() {
        // Regression guard: after "Got it" records the CURRENT version, the
        // sheet must not re-appear. Seeding lastSeen to the newest catalog
        // version (and anything above it) yields nothing pending.
        guard let newest = FeatureHighlightCatalog.all.map(\.version)
            .max(by: { SemVer.compare($0, $1) == .orderedAscending }) else {
            return XCTFail("catalog is empty")
        }
        XCTAssertTrue(FeatureHighlightCatalog.pending(since: newest).isEmpty)
        XCTAssertTrue(FeatureHighlightCatalog.pending(since: "999.0.0").isEmpty)
    }

    func testPendingReturnsOnlyStrictlyNewer() {
        let cutoff = "0.23.12"
        for highlight in FeatureHighlightCatalog.pending(since: cutoff) {
            XCTAssertEqual(
                SemVer.compare(highlight.version, cutoff), .orderedDescending,
                "\(highlight.id) @ \(highlight.version) is not newer than \(cutoff)"
            )
        }
    }

    func testPendingRespectsLimit() {
        XCTAssertLessThanOrEqual(
            FeatureHighlightCatalog.pending(since: "0.0.0", limit: 1).count, 1)
        // An existing user upgrading into the system (lastSeen "0.0.0") sees the
        // headline set — everything, up to the cap.
        let all = FeatureHighlightCatalog.pending(since: "0.0.0", limit: 99)
        XCTAssertEqual(all.count, FeatureHighlightCatalog.all.count)
    }

    // MARK: Headline highlights (Help → What's New)

    /// The on-demand path can't use `pending` — it's empty once the post-update
    /// sheet records the current version (see the test above), which is exactly
    /// when the user reaches for Help → What's New. So `headline` must stand on
    /// its own while still honouring the shared cap.
    func testHeadlineIgnoresSeenStateAndRespectsLimit() {
        XCTAssertFalse(FeatureHighlightCatalog.headline().isEmpty)
        XCTAssertLessThanOrEqual(FeatureHighlightCatalog.headline(limit: 1).count, 1)
        XCTAssertEqual(
            FeatureHighlightCatalog.headline(limit: 99).count,
            FeatureHighlightCatalog.all.count
        )
    }

    func testHighlightIDsAreUnique() {
        let ids = FeatureHighlightCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate feature ids would cross-wire NEW badges")
    }
}
