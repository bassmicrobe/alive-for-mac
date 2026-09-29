import XCTest
@testable import AliveCore

final class FolderScanTests: XCTestCase {
    func testFindSkipsBackupHiddenSymlinkPackagesAndProbes() throws {
        let t = makeTemp()
        t.als("A Project/a.als", Fx.simpleSet())
        t.als("A Project/Backup/a [2026-05-22 012035].als", Fx.simpleSet())
        t.als("A Project/Sub/deep.ALS", Fx.simpleSet())
        t.als("A Project/a.alive-probe.als", Fx.simpleSet())
        t.write("A Project/._a.als", "appledouble")
        t.als(".hidden/h.als", Fx.simpleSet())
        t.als("Thing.app/Contents/x.als", Fx.simpleSet())
        t.write("A Project/readme.txt")
        try FileManager.default.createSymbolicLink(atPath: t.sub("A Project/link"), withDestinationPath: t.sub("A Project/Sub"))

        var found: [String] = []
        let r = FolderScan.find(root: t.path, ext: ".als", includeBackups: false, onFile: { found.append($0) })
        let rel = found.map { String($0.dropFirst(t.path.count + 1)) }.sorted()
        XCTAssertEqual(rel, ["A Project/Sub/deep.ALS", "A Project/a.als"])
        XCTAssertEqual(r.files, 2)
        XCTAssertFalse(r.rootFailed)
        XCTAssertEqual(r.unreadable, 0)

        var withBackups: [String] = []
        _ = FolderScan.find(root: t.path, ext: ".als", includeBackups: true, onFile: { withBackups.append($0) })
        XCTAssertEqual(withBackups.count, 3)
    }

    func testUnreadableAndEmptyRoots() {
        var n = 0
        let r = FolderScan.find(root: "/definitely/not/here", ext: ".als", includeBackups: false, onFile: { _ in n += 1 })
        XCTAssertTrue(r.rootFailed)
        XCTAssertEqual(r.unreadable, 1)
        XCTAssertEqual(n, 0)
        XCTAssertEqual(FolderScan.find(root: "", ext: ".als", includeBackups: false, onFile: { _ in }), FolderScan.Result())
    }

    func testCancelStopsTheWalk() {
        let t = makeTemp()
        t.als("a/a.als", Fx.simpleSet())
        var n = 0
        let r = FolderScan.find(root: t.path, ext: ".als", includeBackups: false, onFile: { _ in n += 1 }, isCancelled: { true })
        XCTAssertEqual(n, 0)
        XCTAssertEqual(r.dirs, 0)
    }

    func testWeighCountsEverythingAndReadsBackupStamps() {
        let t = makeTemp()
        t.write("P Project/Samples/k.wav", String(repeating: "x", count: 1000))
        t.write("P Project/song.als", "12345")
        t.write("P Project/Backup/song [2026-05-22 012035].als", "1")
        t.write("P Project/Backup/song [2026-05-23 101010].als", "1")
        t.write("P Project/Backup/Alive/song [2026-05-24 101010].als", "1")   // Alive subfolder: not history
        t.write("P Project/Backup/notes.txt", "1")
        t.write("P Project/.DS_Store", "junk")
        let w = FolderScan.weigh(root: t.sub("P Project"))
        XCTAssertEqual(w.files, 6)
        XCTAssertEqual(w.bytes, 1000 + 5 + 1 + 1 + 1 + 1)
        XCTAssertEqual(w.saves?.count, 2)
        XCTAssertEqual(Set(w.saves?.map(\.set) ?? []), ["song"])
        XCTAssertNil(FolderScan.weigh(root: t.sub("P Project/Samples")).saves)
        XCTAssertEqual(FolderScan.weigh(root: "").files, 0)
        XCTAssertEqual(FolderScan.weigh(root: t.path, isCancelled: { true }).files, 0)
    }

    func testBackupStampParsing() throws {
        let s = try XCTUnwrap(FolderScan.tryBackupStamp("angelcore [2026-05-22 012035].als"))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: s.when)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 5, 22, 1, 20, 35])
        XCTAssertEqual(s.set, "angelcore")
        XCTAssertEqual(FolderScan.tryBackupStamp("try1 riddik [2026-08-28 140615].als")?.set, "try1 riddik")
        for bad in ["plain.als", "x [2026-13-22 012035].als", "x [2026-02-31 012035].als", "x [2026-05-22 252035].als",
                    "x [2026/05/22 012035].als", "x [2026-05-22 01203].als", "x [2026-05-22 01x035].als", "x [2026-05-22 012035].wav"] {
            XCTAssertNil(FolderScan.tryBackupStamp(bad), bad)
        }
    }

    func testCombine() {
        XCTAssertEqual(FolderScan.combine("/a", "b"), "/a/b")
        XCTAssertEqual(FolderScan.combine("/a/", "b"), "/a/b")
    }
}

final class RefResolverTests: XCTestCase {
    private func env(_ t: TempDir) -> LiveEnvironment {
        t.write("UL/Presets/x.adv"); t.write("Builtin/Devices/a.amxd"); t.write("Core/Samples/c.wav")
        t.write("Packs/Drums/Kick/k.wav")
        var e = LiveEnvironment()
        e.userLibrary = t.sub("UL"); e.builtin = t.sub("Builtin"); e.coreLibrary = t.sub("Core")
        e.setPack("Drums", t.sub("Packs/Drums"))
        return e
    }

    private func ref(_ type: Int, rel: String = "", abs: String = "", pack: String = "") -> FileRefInfo {
        var f = FileRefInfo()
        f.relativePathType = type; f.relativePath = rel; f.absolutePath = abs; f.livePackName = pack
        f.container = "SampleRef"
        return f
    }

    func testEachRootType() {
        let t = makeTemp()
        let e = env(t)
        t.write("Proj/Samples/Recorded/r.wav"); t.write("Other/loop.wav")
        let proj = t.sub("Proj/Sub")
        t.mkdir("Proj/Sub")
        let probe = ProbeCache()
        func res(_ f: FileRefInfo) -> ResolvedRef { RefResolver.resolve(f, projectDir: proj, env: e, probe: probe) }

        XCTAssertEqual(res(ref(1, rel: "../Samples/Recorded/r.wav")).resolvedPath, t.sub("Proj/Samples/Recorded/r.wav"))
        XCTAssertEqual(res(ref(3, rel: "../Samples/Recorded/r.wav")).status, .found)
        XCTAssertEqual(res(ref(5, rel: "Kick/k.wav", pack: "drums")).status, .found)
        XCTAssertEqual(res(ref(6, rel: "Presets/x.adv")).resolvedPath, t.sub("UL/Presets/x.adv"))
        XCTAssertEqual(res(ref(7, rel: "Devices/a.amxd")).status, .found)
        XCTAssertEqual(res(ref(7, rel: "Samples/c.wav")).resolvedPath, t.sub("Core/Samples/c.wav"))   // Core Library fallback
        XCTAssertEqual(res(ref(0, abs: t.sub("Other/loop.wav"))).resolvedPath, t.sub("Other/loop.wav"))
    }

    func testMissingPackEmptyAndMissing() {
        let t = makeTemp()
        let e = env(t)
        func res(_ f: FileRefInfo) -> ResolvedRef { RefResolver.resolve(f, projectDir: t.path, env: e) }
        XCTAssertEqual(res(ref(0)).status, .empty)
        let pack = res(ref(5, rel: "A/b.wav", abs: "/nowhere/b.wav", pack: "Ghost Pack"))
        XCTAssertEqual(pack.status, .missingPack)
        XCTAssertEqual(pack.note, "Ghost Pack")
        let miss = res(ref(1, rel: "../../gone.wav", abs: "/nowhere/gone.wav"))
        XCTAssertEqual(miss.status, .missing)
        XCTAssertEqual(miss.resolvedPath, "/nowhere/gone.wav")
        XCTAssertEqual(res(ref(1, rel: "../../gone.wav")).resolvedPath, "../../gone.wav")
        // A pack that is not installed but whose absolute path still exists is found.
        t.write("Elsewhere/p.wav")
        XCTAssertEqual(res(ref(5, rel: "x/p.wav", abs: t.sub("Elsewhere/p.wav"), pack: "Ghost")).status, .found)
    }

    func testWindowsRelativePathBackslashesAndWindowsAbsoluteIsMissing() {
        let t = makeTemp()
        let e = env(t)
        t.write("P/Samples/s.wav")
        let ok = RefResolver.resolve(ref(3, rel: "Samples\\s.wav", abs: "C:\\Users\\x\\s.wav"), projectDir: t.sub("P"), env: e)
        XCTAssertEqual(ok.status, .found)
        let gone = RefResolver.resolve(ref(0, abs: "C:\\Users\\x\\s.wav"), projectDir: t.sub("P"), env: e)
        XCTAssertEqual(gone.status, .missing)
    }

    func testProbeCacheRemembersForOneScan() {
        let t = makeTemp()
        let p = t.write("f.wav")
        let cache = ProbeCache()
        XCTAssertTrue(cache.exists(p))
        try? FileManager.default.removeItem(atPath: p)
        XCTAssertTrue(cache.exists(p))               // remembered
        XCTAssertFalse(ProbeCache().exists(p))       // a new scan checks again
    }
}

final class RenderIndexTests: XCTestCase {
    private func set(_ path: String) -> SetEntry { var s = SetEntry(); s.path = path; s.name = "song"; return s }

    func testFindRankingAndSkippedFolders() throws {
        let t = makeTemp()
        let root = t.mkdir("Song Project")
        let old = t.write("Song Project/old.wav")
        let new = t.write("Song Project/render/final.mp3")
        t.write("Song Project/Samples/Recorded/rec.wav")
        t.write("Song Project/Backup/b.wav")
        t.write("Song Project/Ableton Project Info/x.wav")
        t.write("Song Project/notes.txt")
        t.write("Song Project/.hidden.wav")
        t.setModified(old, Date(timeIntervalSince1970: 1_000_000))
        t.setModified(new, Date(timeIntervalSince1970: 2_000_000))
        let pins = PreviewPins(dir: t.sub("data"))

        let list = RenderScan.find(set(root + "/song.als"), pins: pins)
        XCTAssertEqual(list.map(\.name), ["final", "old"])
        XCTAssertEqual(list[0].folder, "render")
        XCTAssertEqual(list[0].ext, "MP3")
        XCTAssertEqual(list[0].score, 100)
        XCTAssertEqual(list[1].score, 60)
        XCTAssertEqual(list[0].id, list[0].path)
        XCTAssertEqual(RenderScan.folderScore("Deep/thing"), 20)

        pins.set(root, file: old)
        let pinned = RenderScan.find(set(root + "/song.als"), pins: pins)
        XCTAssertEqual(pinned.map(\.name), ["old", "final"])
        XCTAssertTrue(pinned[0].pinned)
        XCTAssertEqual(RenderScan.projectRoot(set(root + "/song.als")), root)
    }

    func testMissingFolderGivesNothing() {
        XCTAssertEqual(RenderScan.find(set("/no/such/dir/x.als"), pins: PreviewPins(dir: "/tmp/none")).count, 0)
    }

    func testPreviewPinsRoundTripAndFormat() throws {
        let t = makeTemp()
        let a = PreviewPins(dir: t.path)
        XCTAssertEqual(a.get("/P Project"), "")
        a.set("/P Project/", file: "/P Project/render/x.wav")
        a.set("/Q Project", file: "/Q Project/y.wav")
        XCTAssertEqual(a.get("/p project"), "/P Project/render/x.wav")          // case-insensitive, trailing / ignored
        let text = try String(contentsOfFile: t.sub("previews.cfg"))
        XCTAssertTrue(text.contains("/P Project/\t/P Project/render/x.wav"))     // tab-separated, original key kept

        let b = PreviewPins(dir: t.path)                                         // reloaded from disk
        XCTAssertEqual(b.get("/Q Project"), "/Q Project/y.wav")
        b.clear("/Q Project")
        XCTAssertEqual(PreviewPins(dir: t.path).get("/Q Project"), "")
        XCTAssertEqual(PreviewPins(dir: t.path).get("/P Project"), "/P Project/render/x.wav")
    }
}

final class ProjectMetaHomeStoreTests: XCTestCase {
    func testTagsAndNotesRoundTripWithEscapes() throws {
        let t = makeTemp()
        let m = ProjectMeta(dir: t.path)
        let changes = Counter()
        m.onChanged = { changes.bump() }
        let dir = "/Music/Song Project"
        XCTAssertFalse(m.hasAnything(dir))
        m.set(dir, tags: ["Drum", "vocal ", "drum", ""], note: " line one\nline two \\ back = equals\n")
        XCTAssertEqual(changes.value, 1)
        XCTAssertEqual(m.tagsOf(dir), ["Drum", "vocal"])
        XCTAssertEqual(m.noteOf(dir), "line one\nline two \\ back = equals")
        XCTAssertTrue(m.hasAnything(dir.uppercased()))

        let text = try String(contentsOfFile: t.sub("notes.cfg"))
        XCTAssertTrue(text.contains("tags=/Music/Song Project\tDrum, vocal\n"))
        XCTAssertTrue(text.contains("note=/Music/Song Project\tline one\\nline two \\\\ back = equals\n"))

        let reloaded = ProjectMeta(dir: t.path)
        XCTAssertEqual(reloaded.tagsOf(dir), ["Drum", "vocal"])
        XCTAssertEqual(reloaded.noteOf(dir), "line one\nline two \\ back = equals")

        m.set("/Other Project", tags: ["beat", "Alpha"], note: "")
        XCTAssertEqual(m.allTags(), ["Alpha", "beat", "Drum", "vocal"])
        m.set(dir, tags: [], note: "")                       // empty entry disappears
        XCTAssertFalse(m.hasAnything(dir))
        XCTAssertFalse(try String(contentsOfFile: t.sub("notes.cfg")).contains("Song Project"))
        m.set("", tags: ["x"], note: "y")                    // ignored
        XCTAssertEqual(m.tagsOf(""), [])
        XCTAssertEqual(m.noteOf(""), "")
    }

    func testTagHelpersAndBadLines() {
        XCTAssertEqual(ProjectMeta.parseTags("drum, vocal,, Drum ,beat"), ["drum", "vocal", "beat"])
        XCTAssertEqual(ProjectMeta.parseTags(""), [])
        XCTAssertEqual(ProjectMeta.joinTags(["a", "b"]), "a, b")
        XCTAssertEqual(ProjectMeta.unescape("a\\nb\\\\c\\x"), "a\nb\\cx")
        XCTAssertEqual(ProjectMeta.unescape("trailing\\"), "trailing\\")
        XCTAssertEqual(ProjectMeta.escape("a\r\nb\rc"), "a\\nb\\nc")

        let t = makeTemp()
        t.write("notes.cfg", "# c\nnoequals\ntags=/x\nother=/x\tv\ntags=\tv\ntags=/ok\ta, b\n")
        let m = ProjectMeta(dir: t.path)
        XCTAssertEqual(m.tagsOf("/ok"), ["a", "b"])
        XCTAssertEqual(m.allTags(), ["a", "b"])
    }

    func testHomeStorePins() throws {
        let t = makeTemp()
        let h = HomeStore(dir: t.path)
        XCTAssertEqual(h.pins, [])
        XCTAssertTrue(h.togglePin("/a/One.als"))
        XCTAssertTrue(h.togglePin("/a/two.als"))
        XCTAssertFalse(h.togglePin(""))
        XCTAssertTrue(h.isPinned("/A/ONE.als"))
        XCTAssertEqual(try String(contentsOfFile: t.sub("home.cfg")),
                       "# Alive - home page: pinned projects\npin=/a/One.als\npin=/a/two.als\n")

        let again = HomeStore(dir: t.path)
        XCTAssertEqual(again.pins, ["/a/One.als", "/a/two.als"])
        XCTAssertFalse(again.togglePin("/a/one.als"))
        XCTAssertEqual(HomeStore(dir: t.path).pins, ["/a/two.als"])
        t.write("home.cfg", "pin=/x\npin=/X\nfoo=bar\n#c\nnoequals\n")
        XCTAssertEqual(HomeStore(dir: t.path).pins, ["/x"])
    }
}

final class ActivityTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ d: Int, hour: Int = 12, month: Int = 6) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    func testStreaksHoursAndBusiestDay() {
        let today = day(10)
        let stamps = [day(1, hour: 9), day(2, hour: 9), day(3, hour: 9), day(3, hour: 21), day(3, hour: 22),
                      day(8), day(9), day(10)]
        let a = Activity(stamps: stamps, today: today)
        XCTAssertEqual(a.total, 8)
        XCTAssertEqual(a.activeDays, 6)
        XCTAssertEqual(a.longestStreak, 3)
        XCTAssertEqual(a.currentStreak, 3)
        XCTAssertEqual(a.busiestSaves, 3)
        XCTAssertEqual(a.busiestDay, cal.startOfDay(for: day(3)))
        XCTAssertEqual(a.peakHour, 9)                              // 9h and 12h tie: the earlier hour wins
        XCTAssertEqual(a.saves(on: day(3, hour: 1)), 3)
        XCTAssertEqual(a.saves(on: day(4)), 0)
        XCTAssertEqual(a.first, day(1, hour: 9))
        XCTAssertEqual(a.last, day(10))
        XCTAssertEqual(a.hourHistogram.reduce(0, +), 8)
        XCTAssertEqual(a.days.count, 6)
    }

    func testCurrentStreakStartsFromYesterdayWhenTodayIsQuiet() {
        let a = Activity(stamps: [day(8), day(9)], today: day(10))
        XCTAssertEqual(a.currentStreak, 2)
        XCTAssertEqual(Activity(stamps: [day(5)], today: day(10)).currentStreak, 0)
        XCTAssertEqual(Activity.empty.total, 0)
        XCTAssertNil(Activity.empty.first)
        XCTAssertEqual(Activity.empty.peakHour, -1)
    }

    func testBuildUsesCopiesAndOnlyFallsBackToAlsTimeWithoutCopies() {
        let now = day(20)
        var withCopies = SetEntry(); withCopies.path = "/P/A Project/song.als"; withCopies.name = "song"
        withCopies.modified = day(15)                                   // would be a duplicate of the top copy
        var lonely = SetEntry(); lonely.path = "/P/B Project/solo.als"; lonely.name = "solo"; lonely.modified = day(16)
        var backup = SetEntry(); backup.path = "/P/A Project/Backup/x.als"; backup.name = "x"; backup.isBackup = true; backup.modified = day(17)
        var w = FolderScan.Weight()
        w.saves = [FolderScan.Save(when: day(5), set: "song"), FolderScan.Save(when: day(6), set: "Song")]
        let a = Activity.build(dirs: ["/P/A Project"], weights: [w], sets: [withCopies, lonely, backup],
                               previous: nil, now: now)
        XCTAssertEqual(a.total, 3)                                      // two copies + the lonely set
        XCTAssertEqual(a.saves(on: day(15)), 0)
        XCTAssertEqual(a.saves(on: day(16)), 1)
        XCTAssertEqual(a.saves(on: day(17)), 0)
    }

    func testBuildAccumulatesPreviousAndFiltersJunk() {
        let now = day(20)
        let previous = Activity(stamps: [day(1), day(2)], today: now)
        var future = SetEntry(); future.path = "/x/f.als"; future.name = "f"
        future.modified = cal.date(byAdding: .day, value: 30, to: now)!
        var ancient = SetEntry(); ancient.path = "/x/a.als"; ancient.name = "a"
        ancient.modified = Date(timeIntervalSince1970: 100)
        var w = FolderScan.Weight()
        w.saves = [FolderScan.Save(when: day(1), set: "s")]             // repeats a previous stamp
        let a = Activity.build(dirs: ["/x"], weights: [w], sets: [future, ancient], previous: previous, now: now)
        XCTAssertEqual(a.total, 2)
        XCTAssertTrue(Activity.sane(day(3), now: now))
        XCTAssertFalse(Activity.sane(ancient.modified, now: now))
    }

    func testCacheRoundTripAndTruncation() throws {
        let t = makeTemp()
        let a = Activity(stamps: [day(1), day(2), day(2, hour: 13)], today: day(2))
        a.saveCache(dir: t.path)
        let b = Activity.loadCache(dir: t.path, now: day(2))
        XCTAssertEqual(b.total, 3)
        XCTAssertEqual(b.stamps, a.stamps)
        XCTAssertEqual(b.currentStreak, 2)

        // A truncated tail loses only the tail.
        let path = Activity.cachePath(dir: t.path)
        var data = try Data(contentsOf: URL(fileURLWithPath: path))
        data.removeLast(4)
        try data.write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(Activity.loadCache(dir: t.path, now: day(2)).total, 2)

        // Wrong version or missing file reads as empty.
        var w = DotNetWriter(); w.int32(99); w.int32(0)
        try w.data.write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(Activity.loadCache(dir: t.path).total, 0)
        XCTAssertEqual(Activity.loadCache(dir: t.sub("missing")).total, 0)
    }
}
