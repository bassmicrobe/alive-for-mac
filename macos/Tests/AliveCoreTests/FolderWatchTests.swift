import CoreServices
import XCTest
@testable import AliveCore

final class FolderWatchTests: XCTestCase {
    private func flag(_ f: Int) -> FSEventStreamEventFlags { FSEventStreamEventFlags(f) }

    func testRelevanceRules() {
        let created = flag(kFSEventStreamEventFlagItemCreated), removed = flag(kFSEventStreamEventFlagItemRemoved)
        let renamed = flag(kFSEventStreamEventFlagItemRenamed), modified = flag(kFSEventStreamEventFlagItemModified)
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/A Project/a.als", flags: created))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/A Project/a.als", flags: modified))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/A Project/A.ALS", flags: modified))
        XCTAssertFalse(FolderWatch.isRelevant(path: "/r/A Project/Samples/take.wav", flags: modified))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/A Project/Samples/take.wav", flags: created))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/New Project", flags: created | flag(kFSEventStreamEventFlagItemIsDir)))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/x.wav", flags: removed))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r/x.wav", flags: renamed))
        XCTAssertFalse(FolderWatch.isRelevant(path: "/r/x.wav", flags: flag(kFSEventStreamEventFlagItemInodeMetaMod)))
    }

    func testProbesHiddenEntriesAndOverflow() {
        let created = flag(kFSEventStreamEventFlagItemCreated)
        XCTAssertFalse(FolderWatch.isRelevant(path: "/r/p/x.alive-probe.als", flags: created))
        XCTAssertFalse(FolderWatch.isRelevant(path: "/r/p/.DS_Store", flags: created, roots: ["/r"]))
        XCTAssertFalse(FolderWatch.isRelevant(path: "/r/.hidden/a.als", flags: created, roots: ["/r"]))
        // A root that itself lives in a hidden folder is fine.
        XCTAssertTrue(FolderWatch.isRelevant(path: "/home/.cfg/r/a.als", flags: created, roots: ["/home/.cfg/r"]))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r", flags: flag(kFSEventStreamEventFlagMustScanSubDirs)))
        XCTAssertTrue(FolderWatch.isRelevant(path: "/r", flags: flag(kFSEventStreamEventFlagKernelDropped)))
    }

    // MARK: real FSEvents

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        let fired = DispatchSemaphore(value: 0)
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        func hit() { lock.lock(); n += 1; lock.unlock(); fired.signal() }
        /// FSEvents may still report what happened just before the stream started (the temp
        /// folder's own creation): let that settle, then start counting from zero.
        func drain() {
            while fired.wait(timeout: .now() + 1.3) == .success {}
            lock.lock(); n = 0; lock.unlock()
        }
    }

    private func watched(_ dir: TempDir, disabled: [String] = [], settle: TimeInterval = 0.5) -> (FolderWatch, Counter) {
        let counter = Counter()
        let w = FolderWatch(settle: settle, latency: 0.1)
        w.onChanged = { counter.hit() }
        w.watch(roots: [dir.path], disabled: disabled)
        addTeardownBlock { w.stop(); dir.cleanup() }
        if w.isWatching { counter.drain() }
        return (w, counter)
    }

    func testNewSetFiresOnceAfterQuiet() {
        let dir = TempDir("watch")
        let (w, counter) = watched(dir)
        XCTAssertTrue(w.isWatching)
        dir.write("New Project/a.als")
        dir.write("New Project/b.als")     // a burst: one callback
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 2), .timedOut)
        XCTAssertEqual(counter.count, 1)
    }

    func testResavedSetFires() {
        let dir = TempDir("watch")
        let path = dir.write("P Project/a.als", "one")
        let (_, counter) = watched(dir)
        try? Data("two, longer".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 10), .success)
    }

    func testDisabledRootStaysQuiet() {
        let dir = TempDir("watch")
        let (w, counter) = watched(dir, disabled: [dir.path])
        XCTAssertFalse(w.isWatching)
        dir.write("New Project/a.als")
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 2), .timedOut)
    }

    func testMissingRootIsSkippedAndStopIsIdempotent() {
        let w = FolderWatch(settle: 0.2)
        w.watch(roots: ["/definitely/not/here"])
        XCTAssertFalse(w.isWatching)
        w.stop()
        w.stop()
    }

    func testStopSilencesTheWatch() {
        let dir = TempDir("watch")
        let (w, counter) = watched(dir)
        w.stop()
        XCTAssertFalse(w.isWatching)
        dir.write("New Project/a.als")
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 2), .timedOut)
    }

    func testWatchAgainReplacesThePreviousStream() {
        let a = TempDir("watch"), b = TempDir("watch")
        let (w, counter) = watched(a)
        w.watch(roots: [b.path])
        addTeardownBlock { b.cleanup() }
        counter.drain()
        a.write("x/a.als")
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 2), .timedOut)
        b.write("x/a.als")
        XCTAssertEqual(counter.fired.wait(timeout: .now() + 10), .success)
    }
}
