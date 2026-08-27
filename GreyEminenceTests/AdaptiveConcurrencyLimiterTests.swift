import XCTest
@testable import Grey_Eminence

/// Network embedding has to run in parallel — 34,000 sequential round trips is
/// an hour — but a fixed fan-out drew 12,379 throttle responses and silently
/// lost 9,154 records. These pin the retreat-and-recover behaviour that finds
/// the account's real quota instead of guessing it.
final class AdaptiveConcurrencyLimiterTests: XCTestCase {

    // MARK: - The adjustment rule

    func testThrottleHalvesTheLimit() {
        XCTAssertEqual(AdaptiveConcurrencyLimiter.narrowed(from: 12), 6)
        XCTAssertEqual(AdaptiveConcurrencyLimiter.narrowed(from: 6), 3)
    }

    func testLimitNeverFallsBelowOne() {
        // Throttling at one in flight means the provider is down, which is the
        // retry loop's problem. Zero would deadlock every waiter.
        XCTAssertEqual(AdaptiveConcurrencyLimiter.narrowed(from: 1), 1)
        XCTAssertGreaterThanOrEqual(AdaptiveConcurrencyLimiter.narrowed(from: 2), 1)
    }

    func testRecoveryIsSlowerThanRetreat() {
        // Additive up, multiplicative down. Doubling back would re-provoke the
        // throttle it just escaped.
        let after = AdaptiveConcurrencyLimiter.narrowed(from: 12)
        XCTAssertEqual(AdaptiveConcurrencyLimiter.widened(from: after, ceiling: 12), after + 1)
    }

    func testWideningStopsAtTheCeiling() {
        XCTAssertEqual(AdaptiveConcurrencyLimiter.widened(from: 12, ceiling: 12), 12)
    }

    // MARK: - Permits

    func testStartsAtTheConfiguredLimit() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 6, ceiling: 12)
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 6)
    }

    func testStartIsClampedToTheCeiling() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 50, ceiling: 4)
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 4)
    }

    func testThrottleNarrowsTheLiveLimit() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 8, ceiling: 12)
        await limiter.acquire()
        await limiter.release(throttled: true)
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 4)
    }

    func testCleanRunWidensOnlyAfterEnoughSuccesses() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 4, ceiling: 12, successesToWiden: 3)
        for _ in 0..<2 {
            await limiter.acquire()
            await limiter.release(throttled: false)
        }
        var limit = await limiter.currentLimit
        XCTAssertEqual(limit, 4, "widened too eagerly — a brief calm isn't proof the quota rose")

        await limiter.acquire()
        await limiter.release(throttled: false)
        limit = await limiter.currentLimit
        XCTAssertEqual(limit, 5)
    }

    func testSuccessStreakResetsOnAThrottle() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 4, ceiling: 12, successesToWiden: 3)
        for _ in 0..<2 {
            await limiter.acquire()
            await limiter.release(throttled: false)
        }
        await limiter.acquire()
        await limiter.release(throttled: true) // resets the streak, narrows to 2

        await limiter.acquire()
        await limiter.release(throttled: false)
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 2, "a throttle must restart the count, not leave it one short of widening")
    }

    func testNeverExceedsTheLimitUnderConcurrentLoad() async {
        let limiter = AdaptiveConcurrencyLimiter(start: 3, ceiling: 3, successesToWiden: 1000)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<30 {
                group.addTask {
                    await limiter.acquire()
                    await peak.enter()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    await peak.leave()
                    await limiter.release(throttled: false)
                }
            }
        }
        let observed = await peak.highWater
        XCTAssertLessThanOrEqual(observed, 3, "handed out more permits than the limit")
        XCTAssertGreaterThan(observed, 1, "serialized when it should have run in parallel")
    }

    func testEveryWaiterIsEventuallyResumed() async {
        // A permit leak would hang a reindex forever with no error.
        let limiter = AdaptiveConcurrencyLimiter(start: 2, ceiling: 2, successesToWiden: 1000)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<25 {
                group.addTask {
                    await limiter.acquire()
                    await limiter.release(throttled: false)
                }
            }
        }
        // Reaching here at all is the assertion; a lost continuation hangs.
        let limit = await limiter.currentLimit
        XCTAssertGreaterThanOrEqual(limit, 1)
    }

    private actor Peak {
        private var active = 0
        private(set) var highWater = 0
        func enter() { active += 1; highWater = max(highWater, active) }
        func leave() { active -= 1 }
    }
}

/// Backoff shape for throttled Bedrock requests.
final class BedrockBackoffTests: XCTestCase {

    func testThrottlingAndOverloadAreRetried() {
        XCTAssertTrue(BedrockEmbeddingTransport.isTransient(429))
        XCTAssertTrue(BedrockEmbeddingTransport.isTransient(503))
        XCTAssertTrue(BedrockEmbeddingTransport.isTransient(500))
    }

    func testPermissionAndRequestErrorsAreNotRetried() {
        // These fail identically forever; retrying only delays the report.
        XCTAssertFalse(BedrockEmbeddingTransport.isTransient(403))
        XCTAssertFalse(BedrockEmbeddingTransport.isTransient(400))
        XCTAssertFalse(BedrockEmbeddingTransport.isTransient(404))
    }

    func testBackoffGrowsExponentially() {
        let flat = 1.0
        XCTAssertEqual(BedrockEmbeddingTransport.backoffSeconds(attempt: 0, jitter: flat), 0.5, accuracy: 0.001)
        XCTAssertEqual(BedrockEmbeddingTransport.backoffSeconds(attempt: 1, jitter: flat), 1.0, accuracy: 0.001)
        XCTAssertEqual(BedrockEmbeddingTransport.backoffSeconds(attempt: 3, jitter: flat), 4.0, accuracy: 0.001)
    }

    func testBackoffIsCapped() {
        XCTAssertLessThanOrEqual(BedrockEmbeddingTransport.backoffSeconds(attempt: 20, jitter: 1.25), 37.5)
    }

    func testJitterSpreadsRetries() {
        // Without jitter, workers throttled together retry together and stay
        // in lockstep forever.
        let values = Set((0..<40).map { _ in BedrockEmbeddingTransport.backoffSeconds(attempt: 2) })
        XCTAssertGreaterThan(values.count, 1, "retries would fire in lockstep")
    }
}
