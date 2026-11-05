import XCTest
@testable import AliveCore

/// The first audit round: one test for each thing that was wrong.
final class AuditRound1Tests: XCTestCase {
    private func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    /// Takes all permissions from `path` until the test ends (the temp folder is removed after).
    private func lock(_ path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    }

    private func unlock(_ path: String, file: Bool = true) throws {
        try FileManager.default.setAttributes([.posixPermissions: file ? 0o644 : 0o755], ofItemAtPath: path)
    }

    // 1. A link named "Ableton Project Info" must not lead the export into another folder.
    func testAProjectInfoFolderThatIsALinkIsNotFollowedAndIsReported() throws {
        let t = makeTemp()
        t.write("private/id_rsa", "secret")
        t.write("Proj Project/Song.als")
        try FileManager.default.createSymbolicLink(atPath: t.sub("Proj Project/Ableton Project Info"),
                                                   withDestinationPath: t.sub("private"))
        var set = SetEntry()
        set.path = t.sub("Proj Project/Song.als")
        let root = t.mkdir("Out/Song Project_export")

        let skipped = try CollectAll.putProjectInfo(set, root: root)

        XCTAssertEqual(skipped.map(\.name), ["Ableton Project Info"])
        let copied = try FileManager.default.contentsOfDirectory(atPath: root + "/Ableton Project Info")
        XCTAssertEqual(copied, [], "an empty info folder is made instead")
    }

    // 2. A data folder that cannot be entered says nothing about whether the file is there.
    func testAFileInAFolderThatCannotBeEnteredIsInaccessibleNotMissing() throws {
        try XCTSkipIf(geteuid() == 0, "root can enter anything")
        let t = makeTemp()
        let dir = t.mkdir("data")
        let path = t.write("data/notes.cfg", "tags=/P/A Project\tx\n")

        try lock(dir)
        XCTAssertEqual(AppHome.readConfig(path), .inaccessible)
        XCTAssertTrue(AppHome.readStore(path).isUnread)
    }

    // 3. The activity history is the only copy of years of saves: an unread cache is not replaced.
    func testAScanDoesNotReplaceAnActivityCacheItCouldNotRead() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let t = makeTemp()
        let data = t.mkdir("data"), home = t.mkdir("home")
        let xml = Fx.als(live: Fx.main(tempo: 120))
        t.als("music/Alpha Project/alpha.als", xml)
        t.write("music/Alpha Project/Backup/alpha [2026-05-22 012035].als")
        let cache = data + "/activity.cache"
        func index() -> ProjectIndex { ProjectIndex(dir: data, home: home, applicationsDirs: [], settings: Settings()) }

        index().scan(roots: [t.sub("music")])
        let original = try Data(contentsOf: URL(fileURLWithPath: cache))
        XCTAssertEqual(Activity.loadCache(dir: data).total, 1)

        // The first save's copy leaves Backup, another arrives, and the cache cannot be read.
        try FileManager.default.removeItem(atPath: t.sub("music/Alpha Project/Backup/alpha [2026-05-22 012035].als"))
        t.write("music/Alpha Project/Backup/alpha [2026-05-23 012036].als")
        try lock(cache)
        let idx = index()
        idx.scan(roots: [t.sub("music")])
        try unlock(cache)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: cache)), original, "the history was not written over")

        // Read again at the next scan: both saves are in the history.
        idx.scan(roots: [t.sub("music")])
        XCTAssertEqual(Activity.loadCache(dir: data).total, 2)
    }

    // 4. A store that could not be read is read again when something is saved, and the change goes
    // on top of the file; while it still cannot be read the change is refused, not faked. (The pins
    // and the preview pins have the same guard: AuditRound2Tests.)
    func testAStoreThatWasUnreadIsReadAgainOnTheNextSave() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let t = makeTemp()
        let notes = t.write("notes.cfg", "tags=/P/Other Project\tdrum\ntags=/P/A Project\told\n")
        try lock(notes)

        let meta = ProjectMeta(dir: t.path)
        XCTAssertTrue(meta.isUnread)
        XCTAssertEqual(meta.set("/P/A Project", tags: ["x"], note: ""), .unread)

        try unlock(notes)
        XCTAssertEqual(text(notes), "tags=/P/Other Project\tdrum\ntags=/P/A Project\told\n", "nothing was written over it")

        XCTAssertEqual(meta.set("/P/A Project", tags: ["x"], note: ""), .saved)
        XCTAssertFalse(meta.isUnread)
        let reread = ProjectMeta(dir: t.path)
        XCTAssertEqual(reread.tagsOf("/P/Other Project"), ["drum"], "other entries stay")
        XCTAssertEqual(reread.tagsOf("/P/A Project"), ["x", "old"], "the entry the person could not see is kept")
    }

    // 5. A guessable temporary name must not be written through.
    func testSavingNeverWritesThroughALinkAtTheOldTemporaryName() throws {
        let t = makeTemp()
        let victim = t.write("victim.txt", "precious")
        let path = t.sub("notes.cfg")
        try FileManager.default.createSymbolicLink(atPath: path + ".tmp", withDestinationPath: victim)

        try AppHome.writeKeepingBackup("one\n", to: path)
        try AppHome.writeKeepingBackup("two\n", to: path)

        XCTAssertEqual(text(victim), "precious")
        XCTAssertEqual(text(path), "two\n")
        XCTAssertEqual(text(path + ".bak"), "one\n")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: t.path)),
                       ["victim.txt", "notes.cfg", "notes.cfg.bak", "notes.cfg.tmp"], "no temp or part file left")
    }
}
