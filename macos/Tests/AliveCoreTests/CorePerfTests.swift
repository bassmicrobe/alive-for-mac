import XCTest
@testable import AliveCore

/// Memory bound, one walk per project, cache rewrites, O(1) duplicate checks.
final class CorePerfTests: XCTestCase {
    // MARK: inflate

    func testDecompressGrowsWhenTheFirstMappingIsTooSmall() throws {
        let original = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31 >> 3) })
        let gz = try Gzip.compress(original)
        let out = try Gzip.decompress(gz, initialCapacity: 4096)
        XCTAssertEqual(out, original)
        XCTAssertThrowsError(try Gzip.decompress(gz, limit: 1_000_000, initialCapacity: 4096)) {
            XCTAssertEqual($0 as? GzipError, .tooLarge)
        }
    }

    func testSizeHintComesFromTheTrailerAndIsClamped() throws {
        let gz = try Gzip.compress(Data(count: 5_000_000))
        XCTAssertEqual(Gzip.inflatedSizeHint(gz), 5_000_000)
        XCTAssertNil(Gzip.inflatedSizeHint(Data("<xml/>".utf8)))
        var lying = Data([0x1F, 0x8B]) + Data(count: 20)
        lying.replaceSubrange(lying.count - 4..<lying.count, with: [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertLessThanOrEqual(Gzip.inflatedSizeHint(lying) ?? 0, lying.count * 1032)
    }

    func testInflateCapIsSane() {
        XCTAssertEqual(Gzip.maxInflatedBytes, 256 << 20)
    }

    // MARK: byte budget and workers

    func testByteBudgetBoundsTheBytesHeldAtOnce() {
        let budget = ByteBudget(limit: 100)
        let lock = NSLock()
        var peak = 0
        Parallel.forEach(count: 40, workers: 8) { _ in
            let n = budget.acquire(40)
            lock.lock(); peak = max(peak, budget.inUse); lock.unlock()
            usleep(1_000)
            budget.release(n)
        }
        XCTAssertLessThanOrEqual(peak, 100)
        XCTAssertEqual(budget.inUse, 0)
    }

    func testByteBudgetGrantsAnOversizeRequestAlone() {
        let budget = ByteBudget(limit: 10)
        let n = budget.acquire(1_000)           // does not deadlock when nothing else is held
        XCTAssertEqual(budget.inUse, 1_000)
        budget.release(n)
        XCTAssertEqual(budget.inUse, 0)
    }

    func testParallelWorkersCapIsHonoured() {
        let lock = NSLock()
        var running = 0, peak = 0
        Parallel.forEach(count: 30, workers: 2) { _ in
            lock.lock(); running += 1; peak = max(peak, running); lock.unlock()
            usleep(2_000)
            lock.lock(); running -= 1; lock.unlock()
        }
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertLessThanOrEqual(SamplePrints.readers, 3)
    }

    // MARK: one walk per project

    /// The two independent walks the scan used to do (kept here as the reference).
    private enum Old {
        static func weigh(root: String) -> FolderScan.Weight {
            var w = FolderScan.Weight()
            var todo = [URL(fileURLWithPath: root).standardized.path]
            while let dir = todo.popLast() {
                let inBackup = (dir as NSString).lastPathComponent.caseInsensitiveCompare("Backup") == .orderedSame
                guard let entries = FolderScan.list(dir) else { continue }
                for e in entries {
                    if e.isDirectory { todo.append(FolderScan.combine(dir, e.name)); continue }
                    w.bytes += e.size
                    w.files += 1
                    if inBackup, let s = FolderScan.tryBackupStamp(e.name) {
                        if w.saves == nil { w.saves = [] }
                        w.saves?.append(s)
                    }
                }
            }
            return w
        }

        static func renders(root: String) -> [RenderFile] {
            var list: [RenderFile] = []
            walk(dir: root, root: root, into: &list, depth: 0)
            return list
        }

        private static func walk(dir: String, root: String, into list: inout [RenderFile], depth: Int) {
            guard depth <= RenderScan.maxDepth, list.count < RenderScan.maxFiles,
                  let entries = FolderScan.list(dir) else { return }
            var rel = dir.count > root.count ? String(dir.dropFirst(root.count)) : ""
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let folderScore = RenderScan.folderScore(rel)
            var subs: [String] = []
            for e in entries {
                if e.isDirectory { subs.append(e.name); continue }
                if list.count >= RenderScan.maxFiles { return }
                let ext = (e.name as NSString).pathExtension.lowercased()
                guard RenderScan.exts.contains(ext) else { continue }
                var rf = RenderFile()
                rf.path = FolderScan.combine(dir, e.name)
                rf.name = (e.name as NSString).deletingPathExtension
                rf.folder = rel
                rf.modified = e.modified ?? .distantPast
                rf.size = e.size
                rf.score = folderScore
                list.append(rf)
            }
            for name in subs where !RenderScan.skipDirs.contains(name.lowercased()) {
                walk(dir: FolderScan.combine(dir, name), root: root, into: &list, depth: depth + 1)
            }
        }
    }

    private func makeProjectTree(_ t: TempDir) -> String {
        let root = t.mkdir("P Project")
        t.write("P Project/song.als", "als")
        t.write("P Project/mix.wav", "wav-root")
        t.write("P Project/Samples/Recorded/take.wav", "take")
        t.write("P Project/Samples/Imported/kick.aif", "kick")
        t.write("P Project/Backup/song [2026-05-22 012035].als", "b1")
        t.write("P Project/Backup/song [2026-05-23 101010].als", "b2")
        t.write("P Project/Backup/Alive/song [2026-05-23 101010].als", "b3")
        t.write("P Project/Renders/final.mp3", "mp3")
        t.write("P Project/Renders/old/v1.flac", "flac")
        t.write("P Project/Bounces/deep/a/b/c/too-deep.wav", "5 levels")
        t.write("P Project/Bounces/deep/a/b/ok.wav", "4 levels")
        t.write("P Project/Freeze/frozen.wav", "frozen")
        t.write("P Project/Ableton Project Info/x.wav", "info")
        t.write("P Project/notes.txt", "text")
        t.write("P Project/.hidden/h.wav", "hidden")
        return root
    }

    private func assertSameWeights(_ a: FolderScan.Weight, _ b: FolderScan.Weight,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.bytes, b.bytes, file: file, line: line)
        XCTAssertEqual(a.files, b.files, file: file, line: line)
        // Sorted: the order of the saves is not part of the result (Activity sorts them).
        let x = (a.saves ?? []).sorted { $0.when < $1.when }
        let y = (b.saves ?? []).sorted { $0.when < $1.when }
        XCTAssertEqual(x, y, file: file, line: line)
        XCTAssertEqual(a.saves == nil, b.saves == nil, file: file, line: line)
    }

    func testOneWalkGivesTheSameWeightAndRendersAsTwo() {
        let t = makeTemp("walk")
        let root = makeProjectTree(t)
        let both = FolderScan.walkProject(root: root, weigh: true, renders: true)
        assertSameWeights(both.weight, Old.weigh(root: root))
        XCTAssertEqual(both.renders, Old.renders(root: root))

        let onlyRenders = FolderScan.walkProject(root: root, weigh: false, renders: true)
        XCTAssertEqual(onlyRenders.renders, Old.renders(root: root))
        XCTAssertEqual(onlyRenders.weight.files, 0)

        assertSameWeights(FolderScan.weigh(root: root), Old.weigh(root: root))

        // What the fixture is meant to pin: depth cap, skipped folders, Backup history.
        let names = Set(both.renders.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["mix", "final", "v1", "ok"]))
        XCTAssertFalse(names.contains("too-deep") || names.contains("take") || names.contains("frozen")
                       || names.contains("h") || names.contains("x"))
        XCTAssertEqual(both.weight.saves?.count, 2)
    }

    func testTheRenderCapKeepsTheSameFilesInTheSameOrder() {
        let t = makeTemp("cap")
        let root = t.mkdir("C Project")
        for i in 0..<250 { t.write("C Project/r\(i).wav") }
        for d in ["a", "b", "c"] { for i in 0..<250 { t.write("C Project/\(d)/\(d)\(i).wav") } }
        let new = FolderScan.walkProject(root: root, weigh: true, renders: true).renders
        let old = Old.renders(root: root)
        XCTAssertEqual(old.count, RenderScan.maxFiles)
        XCTAssertEqual(new.map(\.path), old.map(\.path))
    }

    func testRenderFindStillPinsAndOrders() {
        let t = makeTemp("find")
        _ = makeProjectTree(t)
        var set = SetEntry()
        set.path = t.sub("P Project/song.als")
        let pins = PreviewPins(dir: t.mkdir("data"))
        XCTAssertEqual(RenderScan.find(set, pins: pins).count, 4)
        pins.set(set.projectDir, file: t.sub("P Project/Renders/old/v1.flac"))
        XCTAssertEqual(RenderScan.find(set, pins: pins).first?.name, "v1")
        XCTAssertTrue(RenderScan.find(set, pins: pins).first?.pinned == true)
    }

    // MARK: ProjectIndex

    private func makeLibrary() -> (t: TempDir, data: String, root: String, home: String) {
        let t = makeTemp("perf")
        let xml = Fx.als(live: Fx.tracks(Fx.track("AudioTrack")) + Fx.main(tempo: 120) + Fx.scale(root: 7, name: 0))
        for v in ["v1", "v2", "v3"] {
            t.als("music/Alpha Project/alpha \(v).als", xml)
            t.write("music/Alpha Project/Backup/alpha \(v) [2026-05-2\(v.last!) 012035].als")
        }
        t.write("music/Alpha Project/render/mix.wav", "wav")
        t.als("music/Beta Project/beta.als", xml)
        return (t, t.mkdir("data"), t.sub("music"), t.mkdir("home"))
    }

    private func mtime(_ p: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date
    }

    func testANoOpRescanLeavesTheCacheFilesAlone() throws {
        let l = makeLibrary()
        let idx = ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings())
        idx.scan(roots: [l.root])
        let cache = l.data + "/index.cache", activity = l.data + "/activity.cache"
        let (c1, a1) = (try Data(contentsOf: URL(fileURLWithPath: cache)), try Data(contentsOf: URL(fileURLWithPath: activity)))
        // Age both files so a rewrite is visible even at coarse mtime resolution.
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cache)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: activity)

        let stats = idx.scan(roots: [l.root])
        XCTAssertEqual(stats.parsed, 0)
        XCTAssertEqual(mtime(cache), old, "index.cache must not be rewritten when nothing changed")
        XCTAssertEqual(mtime(activity), old, "activity.cache must not be rewritten when nothing changed")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: cache)), c1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: activity)), a1)

        // A real change is still written.
        l.t.als("music/Gamma Project/gamma.als", Fx.als(live: Fx.main(tempo: 100)))
        idx.scan(roots: [l.root])
        XCTAssertNotEqual(mtime(cache), old)
    }

    func testLaunchLoadPublishesBeforeDiscoveryAndTheScanDiscoversOnce() {
        let l = makeLibrary()
        ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings()).scan(roots: [l.root])

        let idx = ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings())
        let calls = Counter()
        idx.inventoryLoader = { _ in calls.bump(); return PluginInventory() }
        XCTAssertTrue(idx.loadFromCache(refreshInventory: false))
        XCTAssertEqual(idx.sets.count, 4)
        XCTAssertEqual(calls.value, 0, "the catalog is visible before any plug-in discovery")
        let stats = idx.scan(roots: [l.root])
        XCTAssertEqual(stats.parsed, 0, "the decoded cache is the scan's reuse map")
        XCTAssertEqual(calls.value, 1, "discovery runs once, at the end of the scan")

        idx.loadFromCache()
        XCTAssertEqual(calls.value, 2, "the default still discovers")
    }

    func testRendersAndWeightsAreSharedByAllVersionsOfAProject() throws {
        let l = makeLibrary()
        let idx = ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings())
        idx.scan(roots: [l.root])
        let alpha = idx.sets.filter { $0.projectName == "Alpha" }
        XCTAssertEqual(alpha.count, 3)
        XCTAssertEqual(Set(alpha.map(\.projectSize)).count, 1)
        XCTAssertEqual(Set(alpha.map(\.projectFiles)).count, 1)
        XCTAssertTrue(alpha.allSatisfy { $0.renderNames == ["mix"] })
        XCTAssertEqual(alpha[0].projectFiles, 7)                // 3 sets + 3 copies + render
    }

    func testPartialRescanSkipsTheWeightWalkOnlyForUnchangedProjects() throws {
        let l = makeLibrary()
        let idx = ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings())
        idx.scan(roots: [l.root])
        let alphaBefore = try XCTUnwrap(idx.sets.first { $0.projectName == "Alpha" })

        // A sample lands in Alpha without any .als changing; a full rescan sees it, a partial does not.
        l.t.write("music/Alpha Project/Samples/new.wav", String(repeating: "n", count: 500))
        // Beta gets a new version: its project is walked again in a partial rescan.
        l.t.als("music/Beta Project/beta v2.als", Fx.als(live: Fx.main(tempo: 90)))
        l.t.write("music/Beta Project/render/b.wav", "b")

        idx.scan(roots: [l.root], fullRescan: false)
        let alphaPartial = try XCTUnwrap(idx.sets.first { $0.projectName == "Alpha" })
        XCTAssertEqual(alphaPartial.projectSize, alphaBefore.projectSize)
        XCTAssertEqual(alphaPartial.projectFiles, alphaBefore.projectFiles)
        let betaPartial = try XCTUnwrap(idx.sets.first { $0.name == "beta v2" })
        XCTAssertEqual(betaPartial.projectFiles, 3)             // two sets + render, freshly walked
        XCTAssertEqual(betaPartial.renderNames, ["b"], "renders are always rebuilt")

        idx.scan(roots: [l.root])                               // full (the default)
        let alphaFull = try XCTUnwrap(idx.sets.first { $0.projectName == "Alpha" })
        XCTAssertEqual(alphaFull.projectFiles, alphaBefore.projectFiles + 1)
        XCTAssertEqual(alphaFull.projectSize, alphaBefore.projectSize + 500)
    }

    // MARK: SampleUsage

    func testUsageDuplicateCheckStillCountsEachSetOnce() {
        let t = makeTemp("usage")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.wav(frames: 50, seed: 1), at: root + "/kick.wav")
        let idx = SampleIndex.build(roots: [root], disabled: [])
        let kick = root + "/kick.wav"
        var sets: [SetEntry] = []
        for i in 0..<300 {
            var e = SetEntry()
            e.path = t.sub("Music/P\(i % 30) Project/s\(i).als")
            e.modified = Date(timeIntervalSince1970: Double(i))
            e.samples = [kick, kick]                            // the same sample twice in one set
            e.sampleSizes = [0, 0]
            sets.append(e)
        }
        sets.append(sets[0])                                    // the very same set listed twice
        let u = SampleUsage.compute(index: idx, sets: sets)
        let use = u.of(file: 0)
        XCTAssertEqual(use?.sets.count, 300)
        XCTAssertEqual(use?.projects, 30)
        XCTAssertEqual(use?.lastUsed, Date(timeIntervalSince1970: 299))
        XCTAssertEqual(u.files(ofSet: sets[0].path), [0])
    }
}
