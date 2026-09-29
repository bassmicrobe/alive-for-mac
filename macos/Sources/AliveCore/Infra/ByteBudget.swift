// Mac-only: a counting semaphore measured in bytes. Bounds how much inflated XML the scan
// workers hold at once (a fresh scan used to peak at 2 GB: every worker held a whole set).
import Foundation

public final class ByteBudget: @unchecked Sendable {
    public let limit: Int
    private let cond = NSCondition()
    private var used = 0

    public init(limit: Int) { self.limit = max(1, limit) }

    /// Blocks until `bytes` fit under the limit (a request larger than the whole limit is
    /// granted alone, once nothing else is held, so a huge set still gets parsed). Returns the
    /// amount granted; hand exactly that to `release`.
    public func acquire(_ bytes: Int) -> Int {
        let want = max(0, bytes)
        cond.lock(); defer { cond.unlock() }
        while used > 0 && used + want > limit { cond.wait() }
        used += want
        return want
    }

    /// How often a waiting `acquire(_:isCancelled:)` looks at its flag.
    static let cancelPollInterval: TimeInterval = 0.02

    /// Like `acquire`, but a wait ends as soon as `isCancelled` turns true: nil, nothing held.
    public func acquire(_ bytes: Int, isCancelled: () -> Bool) -> Int? {
        let want = max(0, bytes)
        cond.lock(); defer { cond.unlock() }
        while used > 0 && used + want > limit {
            if isCancelled() { return nil }
            _ = cond.wait(until: Date(timeIntervalSinceNow: Self.cancelPollInterval))
        }
        if isCancelled() { return nil }
        used += want
        return want
    }

    /// Charges bytes that are already in use, without waiting. Memory that has been mapped
    /// must be counted whether or not it fits (waiting for room while holding memory could
    /// deadlock two growing holders); later `acquire`s then wait for it.
    func charge(_ bytes: Int) {
        guard bytes > 0 else { return }
        cond.lock(); used += bytes; cond.unlock()
    }

    public func release(_ granted: Int) {
        cond.lock()
        used -= granted
        cond.broadcast()
        cond.unlock()
    }

    /// Bytes currently held (for tests and diagnostics).
    public var inUse: Int { cond.lock(); defer { cond.unlock() }; return used }
}

extension ByteBudget {
    /// One holder's share of a budget: what it asked for up front, then whatever it actually
    /// maps beyond that. Not thread-safe (one owner); `release()` gives everything back.
    public final class Lease {
        private let budget: ByteBudget
        public private(set) var held: Int

        init(budget: ByteBudget, granted: Int) { self.budget = budget; held = granted }

        /// Makes the lease cover at least `bytes` (charged without waiting).
        func ensure(_ bytes: Int) {
            guard bytes > held else { return }
            budget.charge(bytes - held)
            held = bytes
        }

        /// Gives back what is above `bytes`.
        func shrink(to bytes: Int) {
            guard bytes < held else { return }
            budget.release(held - bytes)
            held = bytes
        }

        public func release() { shrink(to: 0) }
        deinit { release() }
    }

    /// Waits for `bytes` (cancellably) and returns the lease over them; nil when cancelled.
    public func lease(_ bytes: Int, isCancelled: () -> Bool = { false }) -> Lease? {
        acquire(bytes, isCancelled: isCancelled).map { Lease(budget: self, granted: $0) }
    }
}
