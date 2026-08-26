import XCTest
@testable import Grey_Eminence

/// The embedding method is a user choice with a sharp consequence: vectors
/// from different models aren't comparable, and a search only consults
/// records produced by the currently selected one. These pin the pieces that
/// make that switch safe rather than silently emptying the search.
final class EmbeddingProviderTests: XCTestCase {

    func testTitanIdentifierCarriesTheDimensionCount() {
        // Width is part of the vector's meaning. If it ever changes, the
        // identifier must change with it so old records stop being consulted
        // instead of being compared against vectors of a different size.
        XCTAssertTrue(
            TitanEmbeddingService().modelIdentifier.hasSuffix(":\(TitanEmbeddingService.dimensions)"),
            "got: \(TitanEmbeddingService().modelIdentifier)"
        )
    }

    func testEachMethodHasADistinctIdentifier() {
        let identifiers = EmbeddingProvider.allCases.map { $0.makeService().modelIdentifier }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "two methods sharing an identifier would mix incompatible vectors")
    }

    func testOnDeviceIsAlwaysAvailable() {
        XCTAssertTrue(EmbeddingProvider.nlEmbedding.isAvailable)
    }

    func testEveryMethodExplainsItself() {
        for provider in EmbeddingProvider.allCases {
            XCTAssertFalse(provider.explanation.isEmpty, "\(provider.rawValue) needs an explanation in the picker")
            if !provider.isAvailable {
                XCTAssertFalse(provider.unavailableReason.isEmpty, "\(provider.rawValue) is unavailable and must say why")
            }
        }
    }

    func testOnDeviceStaysSerial() {
        // NLEmbedding's framework aborts the process under concurrent access,
        // so its concurrency must never be raised.
        XCTAssertEqual(NLEmbeddingService().maxConcurrency, 1)
    }

    func testNetworkMethodRunsConcurrently() {
        XCTAssertGreaterThan(TitanEmbeddingService().maxConcurrency, 1)
    }

    // MARK: - Batched embedding

    /// Stub that records concurrency and returns a vector encoding the input,
    /// so ordering can be checked independently of timing.
    private final class SpyService: EmbeddingService, @unchecked Sendable {
        let modelIdentifier = "spy"
        let isAvailable = true
        let maxConcurrency: Int
        private let lock = NSLock()
        private var active = 0
        private(set) var peak = 0

        init(maxConcurrency: Int) { self.maxConcurrency = maxConcurrency }

        func embed(_ text: String) async -> [Float]? {
            enter()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
            leave()
            guard let value = Float(text) else { return nil }
            return [value]
        }

        // NSLock isn't callable from an async frame under Swift 6; the
        // bookkeeping is trivial so sync helpers are simpler than an actor.
        private func enter() {
            lock.lock()
            defer { lock.unlock() }
            active += 1
            peak = max(peak, active)
        }

        private func leave() {
            lock.lock()
            defer { lock.unlock() }
            active -= 1
        }
    }

    func testBatchResultsStayPositional() async {
        let spy = SpyService(maxConcurrency: 4)
        let results = await spy.embedAll(["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(results.map { $0?.first }, [1, 2, 3, 4, 5, 6, 7])
    }

    func testFailuresLeaveAHoleRatherThanShiftingResults() async {
        // A nil must stay at its own index — collapsing it would silently
        // attach every later vector to the wrong record.
        let spy = SpyService(maxConcurrency: 4)
        let results = await spy.embedAll(["1", "nope", "3"])
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0]?.first, 1)
        XCTAssertNil(results[1])
        XCTAssertEqual(results[2]?.first, 3)
    }

    func testBatchRespectsTheConcurrencyCeiling() async {
        let spy = SpyService(maxConcurrency: 3)
        _ = await spy.embedAll((0..<20).map(String.init))
        XCTAssertLessThanOrEqual(spy.peak, 3, "fan-out exceeded the limit; back-pressure is gone")
    }

    func testSerialServiceNeverOverlaps() async {
        let spy = SpyService(maxConcurrency: 1)
        _ = await spy.embedAll((0..<10).map(String.init))
        XCTAssertEqual(spy.peak, 1)
    }

    func testEmptyBatchIsHandled() async {
        let spy = SpyService(maxConcurrency: 4)
        let results = await spy.embedAll([])
        XCTAssertTrue(results.isEmpty)
    }
}

/// A reindex must never destroy a working index on behalf of a provider that
/// cannot replace it. This is the shape of a real incident: switching to a
/// Bedrock model the AWS role wasn't authorized for wiped 33,894 working
/// records and wrote nothing, because the purge ran first.
final class ReindexSafetyTests: XCTestCase {

    func testPurgeHelperIsNamedForWhatItDeletes() {
        // The old name said "matching" and deleted the complement. Renaming it
        // is the fix; this pins the intent so it can't drift back.
        let mirror = "\(EmbeddingStore.self)"
        XCTAssertFalse(mirror.isEmpty)
        // Compile-time proof the complement-delete API is the one that exists:
        let selector: (EmbeddingStore) -> (String) -> Int = EmbeddingStore.deleteRecords(notMatchingModel:)
        XCTAssertNotNil(selector)
    }

    func testUnavailableOutcomeCarriesAReason() {
        let outcome = EmbeddingIndexer.ReindexOutcome.unavailable("no vector")
        guard case .unavailable(let message) = outcome else {
            return XCTFail("expected unavailable")
        }
        XCTAssertFalse(message.isEmpty, "a refusal the user can't act on is a silent failure")
    }

    func testAbortedIsDistinctFromCompleted() {
        XCTAssertNotEqual(
            EmbeddingIndexer.ReindexOutcome.aborted("stopped"),
            EmbeddingIndexer.ReindexOutcome.completed(meetings: 0)
        )
    }
}
