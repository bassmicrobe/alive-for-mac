import XCTest
@testable import AliveCore

/// Synthetic fixtures for the October 2026 performance audit; never read the user's library.
final class PerformanceAuditTests: XCTestCase {
    private func fixedLengthLibrary(count: Int) -> SampleIndex {
        var idx = SampleIndex()
        var root = SampleFolder()
        root.path = "/library"
        root.name = "Library"
        root.files = Array(0..<count)
        root.totalSamples = count
        idx.roots = [0]
        idx.folders = [root]
        idx.files = (0..<count).map { i in
            var f = SampleFile()
            f.name = "s\(i).wav"
            f.size = 88_244
            return f
        }
        return idx
    }

    private func importedSet(count: Int) -> SetEntry {
        var s = SetEntry()
        s.path = "/music/Track Project/track.als"
        s.samples = (0..<count).map { "/music/Track Project/Samples/Imported/S\($0).WAV" }
        s.sampleSizes = Array(repeating: 88_244, count: count)
        return s
    }

    func testCopiedReferencesWithManyEqualSizeCandidatesKeepAllNamesakes() {
        var idx = fixedLengthLibrary(count: 100)
        var second = SampleFolder()
        second.path = "/library/Second"
        second.parent = 0
        second.files = [100]
        second.totalSamples = 1
        idx.folders[0].children = [1]
        idx.folders[0].totalSamples += 1
        idx.folders.append(second)
        var twin = idx.files[0]
        twin.folder = 1
        twin.name = "S0.WAV"
        idx.files.append(twin)
        var s = importedSet(count: 3)
        s.samples += [s.samples[0], "/outside/unknown.wav", "/outside/s99.wav"]
        s.sampleSizes += [88_244, 88_244, 0]
        let u = SampleUsage.compute(index: idx, sets: [s])
        XCTAssertEqual(Set(u.files(ofSet: s.path)), [0, 1, 2, 100])
        XCTAssertEqual(u.of(file: 0)?.sets.count, 1, "repeated clips still count the set once")
        XCTAssertEqual(u.of(file: 100)?.projects, 1)
        XCTAssertNil(u.of(file: 99), "a copy without a recorded size is not guessed")
    }

    func testCopyLookupBenchmarkAgainstRepeatedSizeScans() {
        let idx = fixedLengthLibrary(count: 12_000)
        let s = importedSet(count: 600)
        // Reference: the previous size-only candidate loop, including case folding per match.
        let before = Date()
        var oldHits = Set<Int>()
        for path in s.samples {
            let name = (path as NSString).lastPathComponent.lowercased()
            for (i, f) in idx.files.enumerated() where f.size == 88_244 && f.name.lowercased() == name {
                oldHits.insert(i)
            }
        }
        let oldSeconds = Date().timeIntervalSince(before)
        let after = Date()
        let u = SampleUsage.compute(index: idx, sets: [s])
        let newSeconds = Date().timeIntervalSince(after)
        XCTAssertEqual(Set(u.files(ofSet: s.path)), oldHits)
        XCTAssertEqual(u.usedCount, 600)
        // Evidence, no flaky wall-clock acceptance threshold: the functional comparison pins
        // behavior, while the loop now builds one lookup for this size instead of 600 scans.
        print(String(format: "COPY LOOKUP: 12000 equal-size files, 600 refs; old match %.4fs, new full usage %.4fs",
                     oldSeconds, newSeconds))
    }

    func testCopyLookupCanCancelInsideOneLargeSizeGroup() {
        let idx = fixedLengthLibrary(count: 20_000)
        var polls = 0
        let u = SampleUsage.compute(index: idx, sets: [importedSet(count: 1)], isCancelled: {
            polls += 1
            return polls > 6
        })
        XCTAssertEqual(polls, 7)
        XCTAssertEqual(u.usedCount, 0)
    }

    func testFingerprintCancellationDiscardsAHashAfterPartialReads() throws {
        let t = makeTemp("hash-cancel")
        let p = t.sub("recording.wav")
        try Data(repeating: 0x41, count: 8 << 20).write(to: URL(fileURLWithPath: p))
        var polls = 0
        let hash = SamplePrints.print(path: p, isCancelled: {
            polls += 1
            return polls > 3
        })
        XCTAssertEqual(hash, 0, "a partial fingerprint cannot identify duplicates")
        XCTAssertEqual(polls, 4, "cancellation is checked between blocks within a single file")
    }

    func testFingerprintAcrossBlocksKeepsTheOriginalFNVValue() throws {
        let t = makeTemp("hash")
        let p = t.sub("recording.wav")
        let bytes = Data(repeating: 0x52, count: (1 << 20) + 17)
        try bytes.write(to: URL(fileURLWithPath: p))
        let expected = bytes.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        XCTAssertEqual(SamplePrints.print(path: p), expected)
        XCTAssertEqual(SamplePrints.print(path: p, isCancelled: { true }), 0)
    }

    func testPluginMetadataExclusionIsSpecificToBundleAndFormat() {
        let t = makeTemp("plugin-exclusion")
        let known = PluginFixtures.vst3(t, "VST3/Known.vst3")
        _ = PluginFixtures.vst3(t, "VST3/New.vst3")
        let roots = [PluginRoot(path: t.sub("VST3"), kind: .vst3)]
        let inv = PluginBundleScanner.scan(roots, excluding: [PluginRoot(path: known, kind: .vst3)])
        XCTAssertEqual(inv.map(\.name), ["New"])
        XCTAssertEqual(PluginBundleScanner.scan(roots, excluding: [PluginRoot(path: known, kind: .vst2)]).count, 2)
    }

    func testScanReportsUnreadableRootsSeparatelyFromReadableEmptyRoots() {
        let t = makeTemp("scan-health")
        let empty = t.mkdir("empty")
        let missing = t.sub("missing")
        let disabled = t.sub("disabled")
        let idx = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [])
        let inventory: PluginInventory = {
            var inv = PluginInventory()
            var p = InstalledPlugin()
            p.uid = "vst3:test"; p.name = "Test"
            inv.add(p)
            return inv
        }()
        idx.inventoryLoader = { _ in inventory }
        let stats = idx.scan(roots: [empty, missing, disabled], disabledRoots: [disabled])
        XCTAssertEqual(stats.failedRoots, [missing])
        XCTAssertEqual(stats.unreadableFolders, 1)
        XCTAssertEqual(stats.total, 0)
        XCTAssertFalse(stats.cancelled)
        XCTAssertTrue(stats.retainedPreviousCatalog)
        XCTAssertEqual(idx.lastScanStats, stats)
        XCTAssertEqual(idx.inventory.all.count, 1, "project access failure must not skip plug-in discovery")
    }

    func testCancelledDiscoveryDoesNotDiagnoseUntouchedRootsAsUnreadable() {
        let t = makeTemp("scan-cancel")
        let root = t.mkdir("music")
        t.als("music/Song Project/song.als", Fx.als(live: Fx.main(tempo: 120)))
        let idx = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [])
        idx.inventoryLoader = { _ in PluginInventory() }
        idx.scan(roots: [root])
        let previous = idx.sets
        let stats = idx.scan(roots: [t.sub("missing")], isCancelled: { true })
        XCTAssertTrue(stats.cancelled)
        XCTAssertTrue(stats.failedRoots.isEmpty)
        XCTAssertEqual(stats.unreadableFolders, 0)
        XCTAssertFalse(stats.retainedPreviousCatalog)
        XCTAssertEqual(idx.sets, previous)
    }

    func testUnavailableRootRetainsCatalogAndCachesUntilRecovery() throws {
        let t = makeTemp("scan-retain")
        let root = t.mkdir("music")
        let moved = t.sub("offline")
        t.als("music/Song Project/song.als", Fx.als(live: Fx.main(tempo: 120)))
        let data = t.mkdir("data")
        let idx = ProjectIndex(dir: data, home: t.mkdir("home"), applicationsDirs: [])
        idx.inventoryLoader = { _ in PluginInventory() }
        idx.scan(roots: [root])
        let previous = idx.sets
        let files = [IndexCache.path(dir: data), data + "/activity.cache"]
        let caches = try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let stamps = files.map { FileStat.of($0) }
        try FileManager.default.moveItem(atPath: root, toPath: moved)

        let failed = idx.scan(roots: [root])
        XCTAssertTrue(failed.retainedPreviousCatalog)
        XCTAssertEqual(failed.failedRoots, [root])
        XCTAssertEqual(idx.sets, previous)
        XCTAssertEqual(idx.lastScanStats, failed)
        XCTAssertEqual(try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, caches)
        XCTAssertEqual(files.map { FileStat.of($0) }, stamps, "neither cache was rewritten")

        try FileManager.default.moveItem(atPath: moved, toPath: root)
        t.als("music/Song Project/new.als", Fx.als(live: Fx.main(tempo: 90)))
        let recovered = idx.scan(roots: [root])
        XCTAssertFalse(recovered.retainedPreviousCatalog)
        XCTAssertTrue(recovered.failedRoots.isEmpty)
        XCTAssertEqual(idx.sets.count, 2)

        try FileManager.default.removeItem(atPath: t.sub("music/Song Project"))
        let empty = idx.scan(roots: [root])
        XCTAssertFalse(empty.retainedPreviousCatalog)
        XCTAssertTrue(empty.failedRoots.isEmpty)
        XCTAssertTrue(idx.sets.isEmpty, "a readable empty root reflects real deletion")
        XCTAssertTrue(IndexCache.load(dir: data).isEmpty)
    }
}
