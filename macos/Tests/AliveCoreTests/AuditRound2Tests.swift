import XCTest
@testable import AliveCore

/// The second audit round: one test for each thing that was wrong.
final class AuditRound2Tests: XCTestCase {
    private func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    private func lock(_ path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    }

    // 2. A stump left by a crash is not a version: it must not push the good .bak out.
    func testAnEmptyFileDoesNotReplaceTheGoodBackup() throws {
        let t = makeTemp()
        let path = t.sub("notes.cfg")
        try AppHome.writeKeepingBackup("one\n", to: path)
        try AppHome.writeKeepingBackup("two\n", to: path)
        XCTAssertEqual(text(path + ".bak"), "one\n")

        try Data().write(to: URL(fileURLWithPath: path))
        try AppHome.writeKeepingBackup("three\n", to: path)
        XCTAssertEqual(text(path), "three\n")
        XCTAssertEqual(text(path + ".bak"), "one\n", "the empty file was not copied over it")
    }

    // 3. The copy of a Windows-era file is not the writer's .bak, so two saves do not lose it.
    func testTheOriginalOfANonUTF8FileSurvivesTheStoresSaves() throws {
        let t = makeTemp()
        let path = t.sub("notes.cfg")
        let original = Data([UInt8]("tags=/Caf".utf8) + [0xE9, 0x09] + [UInt8]("jazz\n".utf8))     // Latin-1 "é"
        try original.write(to: URL(fileURLWithPath: path))
        _ = AppHome.takeBackupNotices()

        XCTAssertEqual(AppHome.readConfig(path), .recovered(["tags=/Caf\u{E9}\tjazz", ""]))
        XCTAssertEqual(AppHome.takeBackupNotices(), [AppHome.BackupNotice(file: "notes.cfg", copy: "notes.cfg.orig")])

        try AppHome.writeKeepingBackup("tags=/Caf\u{E9}\tjazz\n", to: path)
        try AppHome.writeKeepingBackup("tags=/Caf\u{E9}\tjazz, live\n", to: path)
        try AppHome.writeKeepingBackup("tags=/Caf\u{E9}\tjazz, live, dub\n", to: path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path + ".orig")), original)
    }

    // 7. activity.cache is the only copy of the history: its previous version stays as .bak.
    func testTheActivityCacheKeepsItsPreviousVersion() throws {
        let t = makeTemp()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000), day2 = day1.addingTimeInterval(86_400)
        Activity(stamps: [day1], today: day2).saveCache(dir: t.path)
        Activity(stamps: [day1, day2], today: day2).saveCache(dir: t.path)

        XCTAssertEqual(Activity.loadCache(dir: t.path, now: day2).total, 2)
        let earlier = t.mkdir("earlier")
        try FileManager.default.copyItem(atPath: t.sub("activity.cache.bak"), toPath: earlier + "/activity.cache")
        XCTAssertEqual(Activity.loadCache(dir: earlier, now: day2).total, 1, "the .bak holds the first save alone")
    }

    // 6. A root that would not open stands with its old samples; that walk is not a whole one.
    func testAWalkThatCouldNotOpenARootIsReportedIncomplete() throws {
        try XCTSkipIf(geteuid() == 0, "root can open anything")
        let t = makeTemp()
        t.write("Lib/Kicks/kick.wav")
        t.write("Lib/Pads/pad.wav")
        let root = SampleIndex.norm(t.sub("Lib"))

        let whole = SampleIndex.buildReporting(roots: [root], disabled: [])
        XCTAssertEqual(whole.incompleteRoots, [])
        XCTAssertEqual(whole.index.totalSamples, 2)

        try lock(t.sub("Lib/Pads"))
        let partial = SampleIndex.buildReporting(roots: [root], disabled: [], previous: whole.index)
        XCTAssertEqual(partial.incompleteRoots, [root])
        XCTAssertEqual(partial.index.totalSamples, 2, "the old samples stay")

        // A drive that is not plugged in is not a failed walk: its return walks by itself.
        let ghost = "/Volumes/GhostDrive/Lib"
        XCTAssertEqual(SampleIndex.buildReporting(roots: [ghost], disabled: [], mounted: ["Macintosh HD"]).incompleteRoots, [])
    }

    // 10b. What a write that died left behind goes, but not a file that may still be written.
    func testLeftoverTemporaryFilesAreSweptOnceTheyAreOld() throws {
        let t = makeTemp()
        let id = UUID().uuidString
        let old = [t.write("notes.cfg.tmp-\(id)"), t.write("notes.cfg.bak.part-\(id)"), t.write("home.cfg.tmp")]
        let fresh = t.write("settings.cfg.tmp-\(UUID().uuidString)")
        let real = [t.write("settings.cfg"), t.write("notes.cfg.bak"), t.write("Notes.tmp-draft.txt")]
        for path in old { t.setModified(path, Date().addingTimeInterval(-3600)) }

        XCTAssertEqual(AppHome.sweepLeftoverTemps(dir: t.path), 3)
        for path in old { XCTAssertFalse(FileManager.default.fileExists(atPath: path), path) }
        for path in real + [fresh] { XCTAssertTrue(FileManager.default.fileExists(atPath: path), path) }
    }

    // SR1. While a file cannot be read the pin is kept in memory only, and the caller is told.
    func testPinsSayWhenTheirFileCannotBeRead() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let t = makeTemp()
        let home = t.write("home.cfg", "pin=/a/One.als\n")
        let previews = t.write("previews.cfg", "/P Project\t/P Project/x.wav\n")
        try lock(home)
        try lock(previews)

        let pins = HomeStore(dir: t.path)
        XCTAssertTrue(pins.isUnread)
        let toggled = pins.togglePinReportingSave("/a/two.als")
        XCTAssertTrue(toggled.isPinned)
        XCTAssertEqual(toggled.save, .unread)

        let previewPins = PreviewPins(dir: t.path)
        XCTAssertTrue(previewPins.isUnread)
        XCTAssertEqual(previewPins.set("/Q Project", file: "/Q Project/y.wav"), .unread)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home)
        XCTAssertEqual(pins.togglePinReportingSave("/a/two.als").save, .saved, "read again, then saved on top of the file")
        XCTAssertEqual(text(home), "# Alive - home page: pinned projects\npin=/a/One.als\npin=/a/two.als\n")
    }

    // SR3. The folded texts follow the catalog and the tags; the rule is the same as without them.
    func testTheSearchTextsAreKeptUntilTheCatalogOrTheTagsChange() {
        var set = SetEntry()
        set.path = "/Music/Café Project/Mix.als"
        set.name = "Mix"
        set.projectName = "Café"
        let haystacks = SearchHaystacks()
        var tags: [String: [String]] = [:]
        func cached(_ query: String) -> Bool {
            SetFilter.matchesSearch(set, query: SearchQuery(query)!, haystacks: haystacks,
                                    tagsOf: { tags[$0] ?? [] }, noteOf: { _ in "" })
        }
        func plain(_ query: String) -> Bool {
            SetFilter.matchesSearch(set, query: query, tagsOf: { tags[$0] ?? [] }, noteOf: { _ in "" })
        }
        haystacks.validate(.init(catalog: 1, meta: 1))
        XCTAssertTrue(cached("ｍｉｘ cafe"), "width, case and diacritics are ignored, and every word counts")
        XCTAssertTrue(plain("ｍｉｘ cafe"))
        XCTAssertFalse(cached("mix vocal"))
        XCTAssertFalse(plain("mix vocal"))

        tags[set.projectDir] = ["Vocal"]
        XCTAssertFalse(cached("mix vocal"), "the texts are kept for this revision")
        haystacks.validate(.init(catalog: 1, meta: 2))
        XCTAssertTrue(cached("mix vocal"), "a tag edit bumps the revision and the texts are made again")
        XCTAssertTrue(plain("mix vocal"))
    }
}
