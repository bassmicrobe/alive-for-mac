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

    public func release(_ granted: Int) {
        cond.lock()
        used -= granted
        cond.broadcast()
        cond.unlock()
    }

    /// Bytes currently held (for tests and diagnostics).
    public var inUse: Int { cond.lock(); defer { cond.unlock() }; return used }
}
