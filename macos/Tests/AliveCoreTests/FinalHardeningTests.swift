import XCTest
@testable import AliveCore

/// Inflate budget that follows what is really mapped, cancellation inside the Samples builds,
/// the plugin snapshot and the index.cache save result.
final class FinalHardeningTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        @discardableResult func tick() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    // MARK: inflate budget

    func testTheCeilingSitsAboveTheLargestRealSetAndBelowAGigabyte() {
        // The biggest of 750 real sets inflates to ~92 MB.
        XCTAssertEqual(Gzip.maxInflatedBytes, 512 << 20)
        XCTAssertGreaterThan(Gzip.maxInflatedBytes, 2 * (92 << 20))
    }

    func testTheLeaseFollowsTheActualMappingWhenTheTrailerLiesLow() throws {
        let gz = try Gzip.compress(Data(repeating: 0x41, count: 6 << 20))
        let budget = ByteBudget(limit: 1 << 30)
        // The reservation and the first mapping are both far below the real size (what a
        // trailer that lies low leads to): the output has to grow, and the lease with it.
        let lease = try XCTUnwrap(budget.lease(10))
        XCTAssertEqual(budget.inUse, 10)
        let out = try Gzip.decompress(gz, initialCapacity: 4096, lease: lease)
        XCTAssertEqual(out.count, 6 << 20)
        XCTAssertGreaterThanOrEqual(lease.held, out.count, "the budget is charged for the real mapping")
        XCTAssertEqual(budget.inUse, lease.held)
        lease.release()
        XCTAssertEqual(budget.inUse, 0)
    }

    func testALeaseIsGivenBackWhenInflatingFails() throws {
        let gz = try Gzip.compress(Data(repeating: 0, count: 4 << 20))
        let budget = ByteBudget(limit: 1 << 30)
        let lease = try XCTUnwrap(budget.lease(16))
        XCTAssertThrowsError(try Gzip.decompress(gz, limit: 1 << 20, lease: lease))
        lease.release()
        XCTAssertEqual(budget.inUse, 0)
    }

    func testACancelledWaitForTheBudgetReturnsPromptly() {
        let budget = ByteBudget(limit: 10)
        let held = budget.acquire(10)
        let cancelled = Counter()
        let started = Date()
        let done = expectation(description: "wait ended")
        DispatchQueue.global().async {
            let got = budget.acquire(10, isCancelled: { cancelled.value > 0 })
            XCTAssertNil(got)
            done.fulfill()
        }
        usleep(60_000)
        cancelled.tick()
        wait(for: [done], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        XCTAssertEqual(budget.inUse, 10, "a cancelled wait takes nothing")
        budget.release(held)
        XCTAssertEqual(budget.inUse, 0)
    }

    func testAScanWorkerBlockedOnTheBudgetGivesUpWhenCancelled() throws {
        let t = makeTemp()
        let path = t.path + "/a.als"
        try Gzip.compress(Data("<Ableton/>".utf8)).write(to: URL(fileURLWithPath: path))
        let budget = ByteBudget(limit: 100)
        let held = budget.acquire(100)
        defer { budget.release(held) }
        let info = AlsFile.read(path: path, budget: budget, isCancelled: { true })
        XCTAssertEqual(info.error, "Cancelled")
        XCTAssertEqual(budget.inUse, 100)
    }

    func testASetOverTheCeilingIsUnreadableAndReleasesItsBudget() throws {
        let t = makeTemp()
        let path = t.path + "/big.als"
        try Gzip.compress(Data(repeating: 0x20, count: 2 << 20)).write(to: URL(fileURLWithPath: path))
        let budget = ByteBudget(limit: 1 << 30)
        let info = AlsFile.read(path: path, budget: budget, limit: 1 << 20)
        XCTAssertNotNil(info.error)
        XCTAssertEqual(budget.inUse, 0)
    }

    // MARK: samples cancellation

    private func libraryIndex(files n: Int) -> SampleIndex {
        var idx = SampleIndex()
        var root = SampleFolder(); root.path = "/lib"; root.name = "/lib"; root.totalSamples = n
        root.files = Array(0..<n)
        idx.folders = [root]; idx.roots = [0]
        idx.files = (0..<n).map { i in
            var f = SampleFile(); f.name = "s\(i % 500).wav"; f.size = 100 + Int64(i % 500); f.print = UInt64(i % 500 + 1)
            return f
        }
        return idx
    }

    func testACancelledCopiesSearchStopsEarly() {
        let idx = libraryIndex(files: 40_000)
        let polls = Counter()
        let c = SampleCopies.find(in: idx, isCancelled: { polls.tick(); return true })
        XCTAssertEqual(polls.value, 1)
        XCTAssertTrue(c.files.isEmpty)
        XCTAssertEqual(SampleCopies.find(in: idx).files.count, 40_000, "uncancelled it finds them all")
    }

    func testACancelledUsageComputationStopsEarly() {
        let idx = libraryIndex(files: 20_000)
        var sets: [SetEntry] = []
        for i in 0..<2_000 {
            var s = SetEntry(); s.path = "/p\(i)/a.als"; s.samples = ["/lib/s\(i % 500).wav"]
            sets.append(s)
        }
        let polls = Counter()
        let u = SampleUsage.compute(index: idx, sets: sets, isCancelled: { polls.tick(); return polls.value > 3 })
        XCTAssertLessThanOrEqual(polls.value, 5)
        XCTAssertLessThan(u.usedCount, 500)
        XCTAssertEqual(SampleUsage.compute(index: idx, sets: sets).usedCount, 500)
    }

    func testACancelledListingReturnsNothingToShow() {
        let idx = libraryIndex(files: 20_000)
        let l = SampleLister.listing(index: idx, usage: .empty, copies: .empty, lens: .all, sort: SampleSort(),
                                     open: [], query: "s1", isCancelled: { true })
        XCTAssertTrue(l.rows.isEmpty)
    }

    // MARK: plugin snapshot

    func testAPluginDerivationUsesOnlyItsSnapshot() {
        let idx = ProjectIndex(dir: makeTemp().path, home: makeTemp().path)
        func entry(_ n: String) -> SetEntry {
            var e = SetEntry(); e.path = "/m/\(n).als"; e.name = n; e.plugins = [n]; e.pluginUids = [""]
            e.pluginVendors = [""]; e.pluginVendorConfident = [false]
            return e
        }
        idx.lock.lock(); idx._sets = [entry("Serum")]; idx._generation += 1; idx.lock.unlock()
        let snap = idx.pluginSnapshot()
        idx.lock.lock(); idx._sets = [entry("Serum"), entry("Ghost")]; idx._generation += 1; idx.lock.unlock()

        XCTAssertNotEqual(snap.generation, idx.generation)
        XCTAssertEqual(idx.pluginUsage(of: snap)?.map(\.name), ["Serum"], "the newer catalog does not leak in")
        XCTAssertEqual(Set(idx.pluginUsage().map(\.name)), ["Serum", "Ghost"])
    }

    func testACancelledPluginDerivationRemembersNothing() {
        let idx = ProjectIndex(dir: makeTemp().path, home: makeTemp().path)
        var e = SetEntry(); e.path = "/m/a.als"; e.plugins = ["A"]
        idx.lock.lock(); idx._sets = [e]; idx._generation += 1; idx.lock.unlock()
        XCTAssertNil(idx.pluginUsage(of: idx.pluginSnapshot(), isCancelled: { true }))
        XCTAssertEqual(idx.pluginUsage().map(\.name), ["A"])
    }

    // MARK: cache save result

    func testTheCacheSaveSaysWhatHappened() throws {
        let t = makeTemp()
        var e = SetEntry(); e.path = "/x/a.als"; e.name = "a"
        XCTAssertEqual(IndexCache.save([e], dir: t.path), .written)
        XCTAssertEqual(IndexCache.save([e], dir: t.path), .unchanged)
        e.tempo = 99
        XCTAssertEqual(IndexCache.save([e], dir: t.path), .written)

        let blocker = t.path + "/file"
        try Data("x".utf8).write(to: URL(fileURLWithPath: blocker))
        XCTAssertEqual(IndexCache.save([e], dir: blocker + "/inside"), .failed)
    }
}
