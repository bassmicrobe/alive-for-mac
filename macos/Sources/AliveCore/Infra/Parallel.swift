// Mac-only: replacement for System.Threading.Tasks.Parallel.For with bounded concurrency.
import Foundation

enum Parallel {
    /// Workers = active processor count (at least 2 like upstream's floor, at most `count`).
    static var workerCount: Int { max(2, ProcessInfo.processInfo.activeProcessorCount) }

    /// Runs `body(i)` for every index once, on up to `workerCount` threads, blocking until done.
    /// Indices are handed out one at a time, so slow items do not stall a whole chunk. Once
    /// `isCancelled` returns true no further index is started.
    /// `workers` caps the thread count (I/O-bound work wants a few, not one per core).
    static func forEach(count: Int, workers limit: Int? = nil, isCancelled: () -> Bool = { false },
                        _ body: (Int) -> Void) {
        guard count > 0 else { return }
        let workers = min(max(1, limit ?? workerCount), count)
        let lock = NSLock()
        var next = 0
        func take() -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard next < count, !isCancelled() else { return nil }
            defer { next += 1 }
            return next
        }
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            // One autorelease pool per item: without it everything Foundation autoreleased while
            // handling item i (file contents, bridged strings) lives until the worker exits, i.e.
            // to the end of the whole scan.
            while let i = take() { autoreleasepool { body(i) } }
        }
    }

    /// `forEach` collecting one optional result per index (nil where cancelled or `body` gave nil).
    static func map<T>(count: Int, workers: Int? = nil, isCancelled: () -> Bool = { false },
                       _ body: (Int) -> T?) -> [T?] {
        var results = [T?](repeating: nil, count: count)
        results.withUnsafeMutableBufferPointer { buf in
            let out = buf
            forEach(count: count, workers: workers, isCancelled: isCancelled) { i in out[i] = body(i) }
        }
        return results
    }
}
