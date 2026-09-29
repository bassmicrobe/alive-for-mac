import XCTest
@testable import AliveCore

final class RescueProbeTests: XCTestCase {
    func testSuffixIsTheCatalogsFilter() {
        XCTAssertEqual(RescueProbe.suffix, FolderScan.probeSuffix)
        XCTAssertTrue(RescueProbe.isProbe("/a/b.ALIVE-PROBE.als"))
        XCTAssertFalse(RescueProbe.isProbe("/a/b.als"))
        XCTAssertFalse(RescueProbe.isProbe(""))
        var set = SetEntry()
        set.path = "/a/Song Project/Song.als"
        set.name = "Song"
        XCTAssertEqual(RescueProbe.path(for: set), "/a/Song Project/Song.alive-probe.als")
    }

    func testJournalRememberForgetAndDeduplication() {
        let t = makeTemp()
        let dir = t.mkdir("home")
        RescueProbe.remember("/x/a.alive-probe.als", dir: dir)
        RescueProbe.remember("/X/A.alive-probe.als", dir: dir)        // same file, other case
        RescueProbe.remember("/x/b.alive-probe.als", dir: dir)
        XCTAssertEqual(RescueProbe.journal(dir: dir).count, 2)
        RescueProbe.forget("/x/a.alive-probe.als", dir: dir)
        XCTAssertEqual(RescueProbe.journal(dir: dir), ["/x/b.alive-probe.als"])
        XCTAssertEqual(AppHome.readLines(RescueProbe.journalPath(dir: dir))?.first, "/x/b.alive-probe.als")
    }

    func testCleanupStaleRemovesOnlyProbesAndClearsTheJournal() throws {
        let t = makeTemp()
        let dir = t.mkdir("home")
        let probe = t.write("P Project/Song.alive-probe.als", "probe")
        let ghost = t.sub("P Project/Ghost.alive-probe.als")            // journalled but already gone
        let precious = t.write("P Project/Song.als", "precious")        // a hand-edited journal must not be able to delete this
        for p in [probe, ghost, precious] { RescueProbe.remember(p, dir: dir) }

        XCTAssertEqual(RescueProbe.cleanupStale(dir: dir), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(try String(contentsOfFile: precious), "precious")
        XCTAssertEqual(RescueProbe.journal(dir: dir), [])
        XCTAssertEqual(RescueProbe.cleanupStale(dir: dir), 0)
    }

    func testDropOnlyDeletesProbesAndForgetsThem() {
        let t = makeTemp()
        let dir = t.mkdir("home")
        let probe = t.write("P Project/Song.alive-probe.als")
        let original = t.write("P Project/Song.als")
        RescueProbe.remember(probe, dir: dir)
        RescueProbe.drop(original, dir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        RescueProbe.drop(probe, dir: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(RescueProbe.journal(dir: dir), [])
        RescueProbe.drop("", dir: dir)
    }
}

/// The bisect logic, driven without files or Live: the outcome of a probe is known in advance.
final class RescueBisectTests: XCTestCase {
    private func slot(_ i: Int, kind: PluginKind = .vst3) -> AlsPluginSlot {
        var s = AlsPluginSlot()
        s.uid = "vst3:0000000\(i)-0000-0000-0000-000000000000"
        s.name = "Plugin \(i)"
        s.kind = kind
        return s
    }

    private func session(plugins n: Int, dir: String) -> RescueSession {
        var info = AlsInfo()
        info.path = "/tmp/none/Song.als"
        for i in 1...max(n, 1) where i <= n {
            var p = PluginRef(kind: .vst3)
            p.name = "Plugin \(i)"
            p.uid = slot(i).uid
            info.plugins.append(p)
        }
        var set = SetEntry()
        set.path = info.path
        set.name = "Song"
        return RescueSession(set: set, info: info, inventory: nil, dataDir: dir, logFiles: { [] })
    }

    /// Runs the investigation with `guilty` as the plugins whose presence breaks the set: the
    /// set opens iff every guilty one is switched off.
    private func run(_ s: RescueSession, guilty: Set<String>, rounds: Int = 64) -> Int {
        var probes = 0
        while !s.isFinished, probes < rounds {
            let off = s.suggest()
            if off.isEmpty { break }
            probes += 1
            let opens = guilty.isSubset(of: Set(off.map(\.uid)))
            s.apply(off: off, opened: opens, attempt: nil)
        }
        return probes
    }

    func testOneCulpritIsFoundForEveryPositionAndSize() throws {
        let t = makeTemp()
        for n in [1, 2, 3, 5, 8, 13] {
            for g in 1...n {
                let s = session(plugins: n, dir: t.path)
                let probes = run(s, guilty: [slot(g).uid])
                XCTAssertEqual(s.verdict, .culprit, "n=\(n) g=\(g)")
                XCTAssertEqual(s.culprit?.uid, slot(g).uid, "n=\(n) g=\(g)")
                XCTAssertLessThanOrEqual(probes, 2 * Int(ceil(log2(Double(n)))) + 2, "n=\(n) g=\(g)")
                XCTAssertEqual(s.rescueSelection().map(\.uid), [slot(g).uid])
            }
        }
    }

    func testNotPluginsWhenEverythingDisabledStillFails() throws {
        let t = makeTemp()
        let s = session(plugins: 4, dir: t.path)
        let probes = run(s, guilty: ["never-switched-off"])
        XCTAssertEqual(probes, 1)
        XCTAssertEqual(s.verdict, .notPlugins)
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.culprit)
        XCTAssertTrue(s.rescueSelection().isEmpty)
    }

    func testSeveralCulpritsEndInAWorkingSet() throws {
        let t = makeTemp()
        for guilty in [[2, 5], [1, 2, 3], [1, 8], [4, 5, 6, 7]] {
            let s = session(plugins: 8, dir: t.path)
            let ids = Set(guilty.map { slot($0).uid })
            _ = run(s, guilty: ids)
            XCTAssertEqual(s.verdict, .group, "\(guilty)")
            XCTAssertNil(s.culprit)
            let working = Set(s.working?.map(\.uid) ?? [])
            XCTAssertTrue(ids.isSubset(of: working), "the proven set contains every guilty plugin \(guilty)")
            XCTAssertEqual(Set(s.rescueSelection().map(\.uid)), working)
        }
    }

    func testUserPickedSubsetsAreHonoured() throws {
        let t = makeTemp()
        let s = session(plugins: 6, dir: t.path)
        let g = slot(4).uid
        // A person unticks an arbitrary, uneven set: {1,2,3,4} opens -> suspects shrink to it.
        s.apply(off: [1, 2, 3, 4].map { slot($0) }, opened: true, attempt: nil)
        XCTAssertEqual(Set(s.suspects.map(\.uid)), Set([1, 2, 3, 4].map { slot($0).uid }))
        XCTAssertEqual(s.verdict, .none)
        // {5,6} did not open -> nothing new to rule out among the suspects.
        s.apply(off: [5, 6].map { slot($0) }, opened: false, attempt: nil)
        XCTAssertEqual(s.suspects.count, 4)
        // {2,3} did not open -> 2 and 3 are cleared.
        s.apply(off: [2, 3].map { slot($0) }, opened: false, attempt: nil)
        XCTAssertEqual(Set(s.suspects.map(\.uid)), Set([1, 4].map { slot($0).uid }))
        // {1} did not open -> 4 is the only suspect; disabling it alone opens the set.
        s.apply(off: [slot(1)], opened: false, attempt: nil)
        XCTAssertEqual(s.suspects.map(\.uid), [g])
        XCTAssertEqual(s.suggest().map(\.uid), [g])
        s.apply(off: [slot(4)], opened: true, attempt: nil)
        XCTAssertEqual(s.verdict, .culprit)
        XCTAssertEqual(s.culprit?.uid, g)
    }

    func testWorkingSetKeepsTheSmallestProvenSet() throws {
        let t = makeTemp()
        let s = session(plugins: 5, dir: t.path)
        s.apply(off: (1...5).map { slot($0) }, opened: true, attempt: nil)
        XCTAssertEqual(s.working?.count, 5)
        s.apply(off: [slot(2), slot(3)], opened: true, attempt: nil)
        XCTAssertEqual(s.working?.count, 2)
        s.apply(off: [slot(1), slot(2), slot(3)], opened: true, attempt: nil)
        XCTAssertEqual(s.working?.count, 2, "a larger opened set does not replace the smaller proof")
    }

    func testLogHintNarrowsTheFirstProbeAndTheVerdict() throws {
        let t = makeTemp()
        // Live's log says it died inside Plugin 3.
        var attempt = LoadAttempt()
        attempt.document = "/tmp/none/Song.als"
        attempt.result = .broke
        var hung = PluginLoad()
        hung.name = "plugin 3"                                    // case differs from the .als
        attempt.plugins = [hung]

        let s = session(plugins: 5, dir: t.path)
        s.history = attempt
        s.historySuspect = s.match(hung.name)
        XCTAssertEqual(s.historySuspect?.uid, slot(3).uid)
        XCTAssertEqual(s.suggest().map(\.uid), [slot(3).uid], "the first probe tries the log's suspect alone")

        // It opened with Plugin 3 off -> a culprit on the very first probe.
        s.apply(off: s.suggest(), opened: true, attempt: nil)
        XCTAssertEqual(s.verdict, .culprit)
        XCTAssertEqual(s.culprit?.uid, slot(3).uid)
    }

    func testDidNotOpenWithAHungPluginOutsideTheProbeNamesTheCulprit() throws {
        let t = makeTemp()
        let s = session(plugins: 6, dir: t.path)
        var hung = PluginLoad()
        hung.name = "Plugin 5"
        var a = LoadAttempt()
        a.result = .broke
        a.plugins = [hung]
        // Probe with 1 and 2 off did not open, and Live stopped inside 5, which was still enabled.
        s.apply(off: [slot(1), slot(2)], opened: false, attempt: a)
        XCTAssertEqual(s.suspects.map(\.uid), [slot(5).uid])
        // A hung plugin that WAS disabled is about something else: plain subtraction.
        let s2 = session(plugins: 6, dir: t.path)
        s2.apply(off: [slot(5), slot(2)], opened: false, attempt: a)
        XCTAssertEqual(s2.suspects.count, 4)
    }

    func testMatchFallsBackToLenientNames() throws {
        let t = makeTemp()
        var info = AlsInfo()
        var p = PluginRef(kind: .vst2)
        p.name = "Serum (64 Bit)"
        p.uid = "vst2:1"
        info.plugins = [p]
        var set = SetEntry()
        set.path = "/tmp/none/s.als"
        set.name = "s"
        let s = RescueSession(set: set, info: info, inventory: nil, dataDir: t.path, logFiles: { [] })
        XCTAssertEqual(s.match("Serum_x64")?.uid, "vst2:1")
        XCTAssertNil(s.match("Massive"))
        XCTAssertNil(s.match(""))
    }

    func testTrailIsTyped() throws {
        let t = makeTemp()
        let s = session(plugins: 3, dir: t.path)
        s.apply(off: [slot(1)], opened: true, attempt: nil)
        XCTAssertEqual(s.trail.last, .verdictCulprit(format: "VST3", name: "Plugin 1"))
        XCTAssertEqual(s.trail.first, .opened(disabledCount: 1))
    }
}

/// Real files: probes next to the original, the journal, Live's log, the rescued copy.
final class RescueSessionFileTests: XCTestCase {
    private struct Scratch {
        let t: TempDir
        let home: String
        let als: String
        let set: SetEntry
    }

    private func scratch(devices: [String] = [RescueFx.serum, RescueFx.pumper, RescueFx.rmx]) -> Scratch {
        let t = makeTemp()
        let als = t.als("Song Project/Song.als", RescueFx.set(devices: devices))
        var set = SetEntry()
        set.path = als
        set.name = "Song"
        return Scratch(t: t, home: t.mkdir("home"), als: als, set: set)
    }

    func testPrepareWritesAProbeNextToTheOriginalAndCancelRemovesIt() throws {
        let sc = scratch()
        let before = RescueFx.sha(sc.als)
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home, logFiles: { [] })
        XCTAssertEqual(s.targets.count, 3)
        XCTAssertEqual(s.verdict, .noProbeYet)

        let probe = try s.prepare(disable: [s.targets[0]])
        XCTAssertEqual(probe, sc.t.sub("Song Project/Song.alive-probe.als"))
        XCTAssertEqual((probe as NSString).deletingLastPathComponent, (sc.als as NSString).deletingLastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(RescueProbe.journal(dir: sc.home), [probe])
        XCTAssertEqual(s.round, 1)
        XCTAssertNil(AlsFile.read(path: probe).error)

        // Preparing again replaces the earlier probe rather than piling up.
        _ = try s.prepare(disable: [s.targets[1]])
        XCTAssertEqual(RescueProbe.journal(dir: sc.home).count, 1)
        s.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(RescueProbe.journal(dir: sc.home), [])
        XCTAssertEqual(RescueFx.sha(sc.als), before, "the original is never modified")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sc.t.sub("Song Project")), ["Song.als"])
    }

    func testApplyCleansTheProbeUp() throws {
        let sc = scratch()
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home, logFiles: { [] })
        let probe = try s.prepare(disable: s.targets)
        s.apply(off: nil, opened: false, attempt: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(s.verdict, .notPlugins)
    }

    func testPrepareErrors() throws {
        let sc = scratch()
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home, logFiles: { [] })
        XCTAssertThrowsError(try s.prepare(disable: [])) { XCTAssertEqual($0 as? RescueError, .nothingToDisable) }
        var alien = AlsPluginSlot()
        alien.uid = "vst3:ffffffff-0000-0000-0000-000000000000"
        XCTAssertThrowsError(try s.prepare(disable: [alien])) { XCTAssertEqual($0 as? RescueError, .notFoundInSet) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sc.t.sub("Song Project")), ["Song.als"])
        XCTAssertEqual(RescueProbe.journal(dir: sc.home), [])
    }

    func testUnreadableSetReportsAnErrorInsteadOfTargets() throws {
        let t = makeTemp()
        let bad = t.write("Bad Project/Bad.als", "this is not a set")
        var set = SetEntry()
        set.path = bad
        set.name = "Bad"
        let s = RescueSession(set: set, inventory: nil, dataDir: t.path, logFiles: { [] })
        XCTAssertNotNil(s.error)
        XCTAssertFalse(s.hasTargets)
        XCTAssertTrue(s.suggest().isEmpty)
    }

    func testDiagnosisFromLiveLogSuggestsTheSuspectFirst() throws {
        let sc = scratch()
        LogFx.writeLog(sc.t, version: "11.3.35", lines: [
            LogFx.loading("10:00:00.000000", sc.als),
            LogFx.going("10:00:01.000000", "VST3", "Serum"),
            LogFx.restored("10:00:02.000000", "VST3", "Serum"),
            LogFx.going("10:00:03.000000", "Audio Unit v2", "RMX-1000 Plug-in"),
            LogFx.loading("11:00:00.000000", "/somewhere/else.als"),
        ], age: 0)
        let files = { LiveLog.files(prefsFolders: [sc.t.sub("prefs/Live 11.3.35")]) }
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home, logFiles: files)
        XCTAssertEqual(s.history?.hung?.name, "RMX-1000 Plug-in")
        XCTAssertEqual(s.historySuspect?.name, "RMX-1000 Plug-in")
        XCTAssertEqual(s.suggest().map(\.name), ["RMX-1000 Plug-in"])
        guard case .logStoppedInside(let format, let name, _) = s.trail.first else { return XCTFail("\(s.trail)") }
        XCTAssertEqual([format, name], ["AU", "RMX-1000 Plug-in"])
    }

    func testPollSeesOnlyWhatLiveWritesAfterThePrepare() throws {
        let sc = scratch()
        // An older, failed attempt at the very same document is already in the log.
        let prefs = LogFx.writeLog(sc.t, version: "11.3.35", lines: [
            LogFx.loading("09:00:00.000000", sc.als), LogFx.going("09:00:01.000000", "VST3", "Serum"),
            LogFx.loading("09:30:00.000000", "/x.als"), LogFx.loaded("09:30:03.000000"),
        ])
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home,
                              logFiles: { LiveLog.files(prefsFolders: [prefs]) })
        let probe = try s.prepare(disable: [s.targets[0]])
        XCTAssertNil(s.poll(), "nothing new yet")

        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: prefs + "/Log.txt"))
        try h.seekToEnd()
        try h.write(contentsOf: Data((LogFx.loading("10:00:00.000000", probe) + "\n"
            + LogFx.going("10:00:01.000000", "Audio Unit v2", "RMX-1000 Plug-in") + "\n").utf8))
        var a = s.poll()
        XCTAssertEqual(a?.result, .running)
        XCTAssertEqual(a?.plugins.count, 1)

        try h.write(contentsOf: Data((LogFx.restored("10:00:02.000000", "Audio Unit v2", "RMX-1000 Plug-in") + "\n"
            + LogFx.loaded("10:00:03.000000") + "\n").utf8))
        try h.close()
        a = s.poll()
        XCTAssertEqual(a?.result, .loaded)
        s.apply(off: nil, opened: a?.result == .loaded, attempt: a)
        XCTAssertEqual(s.working?.count, 1)
    }

    func testSaveRescuedNeverOverwritesAndNeverTouchesTheOriginal() throws {
        let sc = scratch()
        let before = RescueFx.sha(sc.als)
        let s = RescueSession(set: sc.set, inventory: nil, dataDir: sc.home, logFiles: { [] })
        XCTAssertThrowsError(try s.saveRescued(disable: []))

        let first = try s.saveRescued(disable: [s.targets[0]])
        let second = try s.saveRescued(disable: [s.targets[0]])
        XCTAssertEqual((first as NSString).lastPathComponent, "Song (rescued).als")
        XCTAssertEqual((second as NSString).lastPathComponent, "Song (rescued) 2.als")
        XCTAssertNotEqual(AlsPatch.targets(AlsFile.read(path: first)).map(\.uid), s.targets.map(\.uid))
        XCTAssertEqual(RescueFx.sha(sc.als), before)
        XCTAssertEqual(s.trail.last, .saved(fileName: "Song (rescued) 2.als"))
    }
}
