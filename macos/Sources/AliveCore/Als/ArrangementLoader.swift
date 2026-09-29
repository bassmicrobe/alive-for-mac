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
    private var cache: [String: Arrangement] = [:]
    private var order: [String] = []
    private var pending: [String] = []          // served from the end: the freshest request first
    private var working = Set<String>()
    private var busy = 0
    private var waiters: [String: [CheckedContinuation<Arrangement, Never>]] = [:]
    private let queue = DispatchQueue(label: "alive.arrangement-loader", qos: .utility,
                                      attributes: .concurrent)

    /// Called for every finished parse, on a background queue.
    public var onReady: (@Sendable (Arrangement) -> Void)?

    public init() {}

    public func cached(_ path: String) -> Arrangement? {
        guard !path.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    /// Requests a parse. The queue is served from the end (the freshest request goes first, the
    /// older ones wait their turn). Asking again for something already being parsed is a no-op:
    /// the answer reaches every subscriber through `onReady`.
    public func request(_ path: String) {
        guard !path.isEmpty else { return }
        lock.lock()
        if working.contains(path) { lock.unlock(); return }
        pending.removeAll { $0 == path }
        pending.append(path)
        let start = busy < Self.maxWorkers
        if start { busy += 1 }
        lock.unlock()
        if start { queue.async { self.work() } }
    }

    /// Async variant: returns the cached arrangement, or waits for the background parse.
    public func load(_ path: String) async -> Arrangement {
        if let a = cached(path) { return a }
        return await withCheckedContinuation { cont in
            lock.lock()
            if let a = cache[path] {      // finished between the check above and now
                lock.unlock()
                cont.resume(returning: a)
                return
            }
            waiters[path, default: []].append(cont)
            lock.unlock()
            request(path)
        }
    }

    private func nextPath() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let path = pending.popLast() else { busy -= 1; return nil }
        working.insert(path)
        return path
    }

    private func work() {
        while let path = nextPath() {
            let arrangement = cached(path) ?? Arrangement.read(path: path)
            store(arrangement, for: path)
            onReady?(arrangement)
        }
    }

    private func store(_ a: Arrangement, for path: String) {
        lock.lock()
        if cache[path] == nil {
            cache[path] = a
            order.append(path)
            while order.count > Self.cacheSize { cache[order.removeFirst()] = nil }
        }
        // Clear the mark whatever happens: otherwise a set could never be requested again.
        working.remove(path)
        let toResume = waiters.removeValue(forKey: path) ?? []
        lock.unlock()
        toResume.forEach { $0.resume(returning: a) }
    }
}
