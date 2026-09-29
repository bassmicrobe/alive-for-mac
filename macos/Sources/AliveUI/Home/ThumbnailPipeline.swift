// Mac-only: the background half of upstream's HomeView.Want/ThumbCache flow — disk cache first, then
// parse + draw at most a few sets at a time, newest request first, skipping what was scrolled away.
import AliveCore
import CoreGraphics
import Foundation

enum ThumbResult: @unchecked Sendable {
    case image(ThumbImage)
    /// The set has no arrangement (or could not be parsed and has nothing to show).
    case empty
    /// Could not be read; not remembered on disk.
    case failed
    /// The asking view went away before the work started.
    case cancelled
}

/// Limits how many tasks run a section at once, serving the freshest waiter first (the tiles on
/// screen were asked for last), and lets cancelled waiters leave the queue without ever running.
final class TaskGate: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let lock = NSLock()
    private let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []

    init(limit: Int) { self.limit = limit }

    /// true once a slot is taken (call `release()` afterwards); false when cancelled first.
    func acquire() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(returning: false)
                } else if running < limit {
                    running += 1
                    lock.unlock()
                    cont.resume(returning: true)
                } else {
                    waiters.append(Waiter(id: id, continuation: cont))
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            let index = waiters.firstIndex { $0.id == id }
            let waiter = index.map { waiters.remove(at: $0) }
            lock.unlock()
            waiter?.continuation.resume(returning: false)
        }
    }

    func release() {
        lock.lock()
        let next = waiters.popLast()
        if next == nil { running -= 1 }
        lock.unlock()
        next?.continuation.resume(returning: true)
    }
}

/// Produces arrangement pictures for tiles and the Sets inspector.
final class ThumbnailPipeline: @unchecked Sendable {
    /// Every picture has this size: 16:9 like the tile's picture area, drawn at 1.5x.
    static let pixelWidth = 480
    static let pixelHeight = 270
    static let aspect = Double(pixelWidth) / Double(pixelHeight)

    let cache: ThumbCache
    let loader = ArrangementLoader()
    private let gate = TaskGate(limit: 3)

    init(dataDir: String) {
        cache = ThumbCache(dataDir: dataDir)
    }

    /// A ready answer without any waiting (memory, then the small PNG on disk).
    func cached(_ setPath: String) -> ThumbResult? {
        Self.result(cache.load(setPath))
    }

    /// Memory only: cheap enough for the main thread.
    func cachedInMemory(_ setPath: String) -> ThumbResult? {
        Self.result(cache.loadFromMemory(setPath))
    }

    private static func result(_ entry: ThumbEntry?) -> ThumbResult? {
        switch entry {
        case .image(let image): return .image(image)
        case .empty: return .empty
        case nil: return nil
        }
    }

    /// The picture for a set: cache, else parse and draw (bounded), then remember it.
    func produce(_ setPath: String) async -> ThumbResult {
        if let hit = cached(setPath) { return hit }
        guard await gate.acquire() else { return .cancelled }
        defer { gate.release() }
        if Task.isCancelled { return .cancelled }
        let arrangement = await loader.load(setPath)
        return finish(arrangement, setPath: setPath)
    }

    /// Draws a parsed arrangement and remembers the answer.
    func finish(_ a: Arrangement, setPath: String) -> ThumbResult {
        if !a.hasContent {
            // Read errors are not remembered: the file may just be on a drive that is switched off.
            if a.error != nil { return .failed }
            cache.save(setPath, image: nil)
            return .empty
        }
        guard let image = ArrangementRender.makeImage(a, width: Self.pixelWidth, height: Self.pixelHeight,
                                                      options: .thumbnail) else { return .failed }
        cache.save(setPath, image: image)
        return .image(ThumbImage(cgImage: image))
    }
}
