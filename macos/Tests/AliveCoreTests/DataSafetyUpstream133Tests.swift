import XCTest
@testable import AliveCore

/// Upstream 9ce4b4b: the .cfg files are written whole with the previous version kept as .bak,
/// and a file that could not be read is never saved over.
final class DataSafetyUpstream133Tests: XCTestCase {
    private func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    func testASaveKeepsThePreviousVersionAsBakAndAnUnchangedSaveLeavesItAlone() throws {
        let t = makeTemp()
        let path = Settings.filePath(dir: t.path)
        var s = Settings()
        s.roots = ["/one"]
        try s.save(dir: t.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak"), "nothing to keep on the first save")

        s.roots = ["/one", "/two"]
        try s.save(dir: t.path)
        XCTAssertTrue(try XCTUnwrap(text(path)).contains("root=/two"))
        XCTAssertTrue(try XCTUnwrap(text(path + ".bak")).contains("root=/one"))
        XCTAssertFalse(try XCTUnwrap(text(path + ".bak")).contains("root=/two"))

        try s.save(dir: t.path)        // the same text again must not push the real previous version out
        XCTAssertFalse(try XCTUnwrap(text(path + ".bak")).contains("root=/two"))
        let left = try FileManager.default.contentsOfDirectory(atPath: t.path).sorted()
        XCTAssertEqual(left, ["settings.cfg", "settings.cfg.bak"], "no temp files left behind")
    }

    /// The stores each go through the same writer; this is only their wiring. The activity cache is
    /// the only copy of the history, so its previous version has to stay as well.
    func testTheOtherStoresKeepABakToo() throws {
        let t = makeTemp()
        let meta = ProjectMeta(dir: t.path)
        meta.set("/P/A Project", tags: ["x"], note: "")
        meta.set("/P/A Project", tags: ["x", "y"], note: "")
        let home = HomeStore(dir: t.path)
        home.togglePin("/P/A Project/a.als")
        home.togglePin("/P/B Project/b.als")
        let pins = PreviewPins(dir: t.path)
        pins.set("/P/A Project", file: "/P/A Project/one.wav")
        pins.set("/P/A Project", file: "/P/A Project/two.wav")
        let day1 = Date(timeIntervalSince1970: 1_700_000_000), day2 = day1.addingTimeInterval(86_400)
        Activity(stamps: [day1], today: day2).saveCache(dir: t.path)
        Activity(stamps: [day1, day2], today: day2).saveCache(dir: t.path)

        let files = Set(try FileManager.default.contentsOfDirectory(atPath: t.path))
        XCTAssertTrue(files.isSuperset(of: ["notes.cfg.bak", "home.cfg.bak", "previews.cfg.bak", "activity.cache.bak"]), "\(files)")
        XCTAssertTrue(try XCTUnwrap(text(t.sub("home.cfg.bak"))).contains("pin=/P/A Project/a.als"))
        XCTAssertFalse(try XCTUnwrap(text(t.sub("home.cfg.bak"))).contains("b.als"))

        let earlier = t.mkdir("earlier")
        try FileManager.default.copyItem(atPath: t.sub("activity.cache.bak"), toPath: earlier + "/activity.cache")
        XCTAssertEqual(Activity.loadCache(dir: t.path, now: day2).total, 2)
        XCTAssertEqual(Activity.loadCache(dir: earlier, now: day2).total, 1, "the .bak holds the first save alone")
    }

    /// A file there but unreadable (another program holds it, no permission) says nothing about
    /// what it holds; saving this copy's defaults over it would erase the owner's data. A file
    /// that is read but is not text was backed up by the reader, and overwriting it is the way out.
    func testAFileThatCouldNotBeReadIsNotSavedOver() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let t = makeTemp()
        let path = Settings.filePath(dir: t.path)
        let original = "root=/precious\nroot=/also\n"
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        var s = Settings.load(dir: t.path)
        XCTAssertTrue(s.isUnread)
        s.roots = ["/new"]
        XCTAssertNoThrow(try s.save(dir: t.path))
        s.reloadRoots(dir: t.path)
        XCTAssertEqual(s.roots, ["/new"], "the roots in hand are kept rather than none")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        XCTAssertEqual(text(path), original, "the file was not touched")

        // Not text: backed up, and free to be replaced.
        let junk = makeTemp()
        try Data([0x72, 0x00, 0xFF, 0x00]).write(to: URL(fileURLWithPath: Settings.filePath(dir: junk.path)))
        var fresh = Settings.load(dir: junk.path)
        XCTAssertFalse(fresh.isUnread)
        fresh.roots = ["/new"]
        try fresh.save(dir: junk.path)
        XCTAssertEqual(Settings.load(dir: junk.path).roots, ["/new"])
    }
}
