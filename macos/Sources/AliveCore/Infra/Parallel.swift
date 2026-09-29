// Mac-only: replacement for System.Threading.Tasks.Parallel.For with bounded concurrency.
import Foundation

enum Parallel {
    /// Workers = active processor count (at least 2 like upstream's floor, at most `count`).
    static var workerCount: Int { max(2, ProcessInfo.processInfo.activeProcessorCount) }

    /// Runs `body(i)` for every index once, on up to `workerCount` threads, blocking until done.
    /// Indices are handed out one at a time, so slow items do not stall a whole chunk. Once
    /// `isCancelled` returns true no further index is started.
    static func forEach(count: Int, isCancelled: () -> Bool = { false }, _ body: (Int) -> Void) {
        guard count > 0 else { return }
        let workers = min(workerCount, count)
        let lock = NSLock()
        var next = 0
        func take() -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard next < count, !isCancelled() else { return nil }
            defer { next += 1 }
            return next
        }
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            while let i = take() { body(i) }
        }
    }

    /// `forEach` collecting one optional result per index (nil where cancelled or `body` gave nil).
    static func map<T>(count: Int, isCancelled: () -> Bool = { false }, _ body: (Int) -> T?) -> [T?] {
        var results = [T?](repeating: nil, count: count)
        results.withUnsafeMutableBufferPointer { buf in
            let out = buf
            forEach(count: count, isCancelled: isCancelled) { i in out[i] = body(i) }
        }
        return results
    }
}
