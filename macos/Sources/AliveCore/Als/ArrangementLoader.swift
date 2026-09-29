// Port of src/ArrangementLoader.cs (WinForms Control marshalling dropped)
import Foundation

/// Reads arrangements in the background and keeps the last few in memory. Parsing a set takes
/// from 100 ms to a second, so it must never happen on the UI thread: stepping through a list
/// with the arrow keys would freeze the window on every row.
///
/// Two ways to use it:
/// - `request(path)` + `onReady` (upstream's `Ready` event; the callback arrives on a background
///   queue — hop to the main actor yourself), or
/// - `await load(path)`.
public final class ArrangementLoader: @unchecked Sendable {
    /// One arrangement is about 0.4 MB; at any moment one is on screen in the detail panel and
    /// one full screen, while the home tiles live off their own cache of finished pictures.
    static let cacheSize = 12
    /// Parsing is pure CPU; more than three workers is not worth taking for background work.
    static let maxWorkers = 3

    private let lock = NSLock()
    /// What the file looked like when it was parsed: a re-saved set has another stamp, so an
    /// old picture of it is never served.
    private struct Stamp: Equatable {
        let size: Int64
        let modified: Date
        static func of(_ path: String) -> Stamp? {
            FileStat.of(path).map { Stamp(size: $0.size, modified: $0.modified) }
        }
    }
    private struct Entry {
        let arrangement: Arrangement
        let stamp: Stamp?
    }

    private var cache: [String: Entry] = [:]
    private var order: [String] = []
    private var pending: [String] = []          // served from the end: the freshest request first
    private var working = Set<String>()
    private var busy = 0
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Arrangement, Never>
    }
    private var waiters: [String: [Waiter]] = [:]
    /// Paths somebody asked for with `request` (not only through `load`): kept in the queue even
    /// when every `load` waiter has left.
    private var requestedDirectly = Set<String>()
    private let queue = DispatchQueue(label: "alive.arrangement-loader", qos: .utility,
                                      attributes: .concurrent)

    /// Called for every finished parse, on a background queue.
    public var onReady: (@Sendable (Arrangement) -> Void)?

    public init() {}

    public func cached(_ path: String) -> Arrangement? {
        guard !path.isEmpty else { return nil }
        return lookup(path, stamp: Stamp.of(path))
    }

    /// The cached arrangement when it still matches the file on disk; a stale one is dropped.
    private func lookup(_ path: String, stamp: Stamp?) -> Arrangement? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[path] else { return nil }
        if entry.stamp == stamp { return entry.arrangement }
        cache[path] = nil
        order.removeAll { $0 == path }
        return nil
    }

    /// Requests a parse. The queue is served from the end (the freshest request goes first, the
    /// older ones wait their turn). Asking again for something already being parsed is a no-op:
    /// the answer reaches every subscriber through `onReady`.
    public func request(_ path: String) {
        guard !path.isEmpty else { return }
        lock.lock()
        requestedDirectly.insert(path)
        lock.unlock()
        enqueue(path)
    }

    private func enqueue(_ path: String) {
        lock.lock()
        if working.contains(path) { lock.unlock(); return }
        pending.removeAll { $0 == path }
        pending.append(path)
        let start = busy < Self.maxWorkers
        if start { busy += 1 }
        lock.unlock()
        if start { queue.async { self.work() } }
    }

    /// Async variant: returns the cached arrangement, or waits for the background parse. A task
    /// that is cancelled while it waits leaves at once, with an arrangement whose `error` is
    /// "cancelled" (the caller checks `Task.isCancelled` first); a parse nobody waits for any more
    /// and that has not started is dropped from the queue.
    public func load(_ path: String) async -> Arrangement {
        // Nothing to parse (and nobody to ever resume a waiter): answer at once.
        guard !path.isEmpty else {
            var empty = Arrangement()
            empty.error = "no path"
            return empty
        }
        let stamp = Stamp.of(path)
        if let a = lookup(path, stamp: stamp) { return a }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Arrangement, Never>) in
                lock.lock()
                if let entry = cache[path], entry.stamp == stamp {      // finished between the check above and now
                    lock.unlock()
                    cont.resume(returning: entry.arrangement)
                    return
                }
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(returning: Self.cancelledArrangement)
                    return
                }
                waiters[path, default: []].append(Waiter(id: id, continuation: cont))
                lock.unlock()
                enqueue(path)
            }
        } onCancel: {
            self.abandon(path, waiter: id)
        }
    }

    static var cancelledArrangement: Arrangement {
        var a = Arrangement()
        a.error = "cancelled"
        return a
    }

    /// Number of tasks waiting for a parse of `path`.
    func waiterCount(_ path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return waiters[path]?.count ?? 0
    }

    private func abandon(_ path: String, waiter id: UUID) {
        lock.lock()
        var left: Waiter?
        if var list = waiters[path], let i = list.firstIndex(where: { $0.id == id }) {
            left = list.remove(at: i)
            waiters[path] = list.isEmpty ? nil : list
            if list.isEmpty, !requestedDirectly.contains(path) { pending.removeAll { $0 == path } }
        }
        lock.unlock()
        left?.continuation.resume(returning: Self.cancelledArrangement)
    }

    private func nextPath() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let path = pending.popLast() else { busy -= 1; return nil }
        working.insert(path)
        return path
    }

    private func work() {
        while let path = nextPath() {
            // Stamp first: a save during the parse leaves the entry stale rather than fresh.
            let stamp = Stamp.of(path)
            let arrangement = lookup(path, stamp: stamp) ?? Arrangement.read(path: path)
            store(arrangement, for: path, stamp: stamp)
            onReady?(arrangement)
        }
    }

    private func store(_ a: Arrangement, for path: String, stamp: Stamp?) {
        lock.lock()
        if cache[path]?.stamp != stamp || cache[path] == nil {
            if cache[path] == nil { order.append(path) }
            cache[path] = Entry(arrangement: a, stamp: stamp)
            while order.count > Self.cacheSize { cache[order.removeFirst()] = nil }
        }
        // Clear the mark whatever happens: otherwise a set could never be requested again.
        working.remove(path)
        let toResume = waiters.removeValue(forKey: path) ?? []
        requestedDirectly.remove(path)
        lock.unlock()
        toResume.forEach { $0.continuation.resume(returning: a) }
    }
}
