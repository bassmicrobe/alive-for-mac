import XCTest
@testable import AliveCore

/// Remounted volumes re-check found samples, sample walks never lose a root to an unplugged drive,
/// unreadable sets are never ready, and a stale status calculation is never published.
final class CatalogRoundFourTests: XCTestCase {
    private let base: Set<String> = ["Macintosh HD"]

    private func setEntry(_ path: String = "/m/A Project/A.als", samples: [String] = [], error: String = "") -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = "A"
        e.modified = Date(timeIntervalSince1970: 1_000)
        e.samples = samples
        e.error = error
        return e
    }

    // MARK: 9

    func testFoundSamplesOnAReappearedVolumeAreRechecked() {
        let found = setEntry("/m/A Project/A.als", samples: ["/Volumes/GhostDrive/a.wav", "/Users/me/b.wav"])
        let other = setEntry("/m/B Project/B.als", samples: ["/Volumes/Elsewhere/c.wav"])
        let local = setEntry("/m/C Project/C.als", samples: ["/Users/me/d.wav"])
        let recheck = ProjectIndex.setsToRecheck(sets: [found, other, local], facts: [:],
                                                 mounted: base.union(["GhostDrive"]), appeared: ["GhostDrive"])
        XCTAssertEqual(recheck, [found.path])
        XCTAssertTrue(ProjectIndex.setsToRecheck(sets: [found], facts: [:], mounted: base, appeared: []).isEmpty)
    }

    func testVolumesDidChangeReportsThoseSetsAndOfflineReferencesStillCount() {
        let t = makeTemp("recheck")
        let mounted = MountBox(base.union(["GhostDrive"]))
        let index = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { mounted.value }
        let found = setEntry(samples: ["/Volumes/GhostDrive/a.wav"])
        index.lock.lock(); index._sets = [found]; index._mounted = mounted.value; index.lock.unlock()

        mounted.value = base                                   // unplugged: offline, nothing to re-read
        XCTAssertTrue(index.volumesDidChange().recheck.isEmpty)
        mounted.value = base.union(["GhostDrive"])             // plugged in again: the set must be read again
        XCTAssertEqual(index.volumesDidChange().recheck, [found.path])
    }

    // MARK: 10

    private let ghost = "/Volumes/GhostDrive/Lib"

    private func cachedGhost(_ t: TempDir) -> SampleIndex {
        t.write("Lib/Drums/kick.wav", "kick")
        var idx = SampleIndex.walk(root: t.sub("Lib"), known: nil, found: { _ in }, isCancelled: { false })!
        for i in idx.folders.indices {
            idx.folders[i].path = ghost + idx.folders[i].path.dropFirst(t.sub("Lib").count)
        }
        return idx
    }

    func testADriveThatVanishesDuringTheWalkKeepsItsPreviousTree() {
        let t = makeTemp("walk-vanish")
        let previous = cachedGhost(t)
        // Mounted when the scan began, gone by the time the walk is over.
        let built = SampleIndex.build(roots: [ghost], disabled: [], previous: previous,
                                      mounted: base.union(["GhostDrive"]), mountedNow: { self.base })
        XCTAssertEqual(built.roots.count, 1)
        XCTAssertEqual(built.totalSamples, 1)
        XCTAssertEqual(built.folders[built.roots[0]].path, ghost)
    }

    func testAWalkThatFailsOnAnExistingFolderKeepsItsPreviousTree() throws {
        let t = makeTemp("walk-denied")
        let lib = t.mkdir("Lib")
        t.write("Lib/a.wav", "aaaa")
        let local = t.mkdir("Local")
        t.write("Local/loop.wav", "loop")
        let previous = SampleIndex.build(roots: [lib, local], disabled: [], previous: nil, mounted: base)
        XCTAssertEqual(previous.totalSamples, 2)

        chmod(lib, 0o000)
        defer { chmod(lib, 0o755) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: lib), "permissions are not enforced here")
        let built = SampleIndex.build(roots: [lib, local], disabled: [], previous: previous, mounted: base)
        XCTAssertEqual(built.roots.count, 2, "the unreadable root is kept, not dropped")
        XCTAssertEqual(built.totalSamples, 2)
    }

    func testARootThatIsReallyGoneDropsOut() throws {
        let t = makeTemp("walk-gone")
        let lib = t.mkdir("Lib")
        t.write("Lib/a.wav", "aaaa")
        let previous = SampleIndex.build(roots: [lib], disabled: [], previous: nil, mounted: base)
        try FileManager.default.removeItem(atPath: lib)
        let built = SampleIndex.build(roots: [lib], disabled: [], previous: previous, mounted: base)
        XCTAssertTrue(built.roots.isEmpty)
    }

    // MARK: 11

    func testAnUnreadableSetIsNeverReady() {
        let broken = setEntry(error: "not a gzip file")
        let status = SetStatus.derive(entry: broken, offlinePaths: [], newestRender: nil, mounted: base,
                                      pluginsKnown: true)
        XCTAssertEqual(status.readiness, .unreadable)
        XCTAssertTrue(status.isUnreadable)
        XCTAssertEqual(SetStatus.basic(broken, pluginsKnown: true).readiness, .unreadable)
        XCTAssertEqual(SetStatus.derive(entry: setEntry(), offlinePaths: [], newestRender: nil, mounted: base,
                                        pluginsKnown: true).readiness, .ready)
    }

    func testUnreadableSetsFallOutOfTheReadyFilterAndShowAsTheirOwnFacet() {
        let ok = setEntry("/m/ok.als"), broken = setEntry("/m/bad.als", error: "damaged")
        let statuses = [ok.path: SetStatus(), broken.path: SetStatus(isUnreadable: true)]
        var filter = SetFilter()
        filter.readiness = [.ready]
        let lookup: (SetEntry) -> SetStatus = { statuses[$0.path] ?? SetStatus() }
        XCTAssertTrue(filter.matches(ok, tagsOf: { _ in [] }, statusOf: lookup))
        XCTAssertFalse(filter.matches(broken, tagsOf: { _ in [] }, statusOf: lookup))
        filter.readiness = [.unreadable]
        XCTAssertTrue(filter.matches(broken, tagsOf: { _ in [] }, statusOf: lookup))
    }

    func testACorruptFileIsUnreadableAfterARealScan() throws {
        let t = makeTemp("unreadable-scan")
        let root = t.mkdir("music")
        t.write("music/Bad Project/Bad.als", "this is not gzip")
        let index = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { self.base }
        index.scan(roots: [root])
        let set = try XCTUnwrap(index.sets.first)
        XCTAssertFalse(set.error.isEmpty)
        XCTAssertEqual(index.statuses[set.path]?.readiness, .unreadable)
    }

    // MARK: 12

    func testAStatusRunThatLostTheRaceDoesNotOverwriteTheNewerState() {
        let t = makeTemp("status-race")
        let mounted = MountBox(base.union(["GhostDrive"]))
        let index = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { mounted.value }
        let found = setEntry(samples: ["/Volumes/GhostDrive/a.wav"])
        index.lock.lock(); index._sets = [found]; index._mounted = mounted.value; index.lock.unlock()

        // While the first calculation (with the drive mounted) is under way, the drive is unplugged
        // and that change publishes its own statuses. The older result must not replace them.
        index.beforeStatusPublish = {
            mounted.value = self.base
            index.volumesDidChange()
        }
        index.rebuildStatuses()
        XCTAssertEqual(index.statuses[found.path]?.offlineFiles, 1, "the unplugged drive wins")
    }
}
