import Foundation

/// Concurrency ceiling that finds the provider's real throughput instead of
/// guessing it.
///
/// A fixed number can't be right: too high and the provider throttles — a
/// first full index at eight workers drew 12,379 HTTP 429s and lost 9,154
/// records — too low and a 34,000-request rebuild takes far longer than the
/// quota requires. The quota also isn't a published constant; it varies by
/// account, region and what else is running.
///
/// So: additive increase, multiplicative decrease, the same shape TCP uses.
/// Halve on a throttle, creep back up after a run of clean responses. It
/// settles just under whatever the account actually allows.
actor AdaptiveConcurrencyLimiter {
    /// Never exceed this many in flight.
    let ceiling: Int
    /// Clean responses required before widening by one. High enough that a
    /// brief calm doesn't immediately re-provoke the throttle that just fired.
    private let successesToWiden: Int

    private var limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var consecutiveSuccesses = 0

    init(start: Int = 6, ceiling: Int = 12, successesToWiden: Int = 20) {
        self.ceiling = max(1, ceiling)
        self.limit = min(max(1, start), max(1, ceiling))
        self.successesToWiden = max(1, successesToWiden)
    }

    var currentLimit: Int { limit }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        // The permit is charged by whoever resumes this waiter, not here.
        // Counting it after the continuation returns leaves a window where
        // `inFlight` is stale, and a concurrent `acquire` takes the fast path
        // against a count that has already been spoken for — which handed out
        // six permits against a limit of three.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Return a permit, reporting whether the provider throttled the request.
    func release(throttled: Bool) {
        inFlight = max(0, inFlight - 1)
        if throttled {
            consecutiveSuccesses = 0
            limit = Self.narrowed(from: limit)
        } else {
            consecutiveSuccesses += 1
            if consecutiveSuccesses >= successesToWiden {
                consecutiveSuccesses = 0
                limit = Self.widened(from: limit, ceiling: ceiling)
            }
        }
        resumeWaitersIfRoom()
    }

    private func resumeWaitersIfRoom() {
        while inFlight < limit, !waiters.isEmpty {
            inFlight += 1
            waiters.removeFirst().resume()
        }
    }

    /// Halve, never below one — a provider that throttles at one request in
    /// flight is down, not busy, and that's the retry loop's problem.
    static func narrowed(from limit: Int) -> Int {
        max(1, limit / 2)
    }

    /// Step up by one. Doubling would re-provoke the throttle it just escaped:
    /// recovery should be slower than retreat.
    static func widened(from limit: Int, ceiling: Int) -> Int {
        min(ceiling, limit + 1)
    }
}
