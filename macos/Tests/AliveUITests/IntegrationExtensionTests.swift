import XCTest
import AliveCore
@testable import AliveUI

final class URLCommandParseTests: XCTestCase {
    private func parse(_ s: String) -> URLCommand? { URL(string: s).flatMap(URLCommand.parse) }

    func testSimpleCommands() {
        XCTAssertEqual(parse("alive://home"), .home)
        XCTAssertEqual(parse("alive://latest"), .latest)
        XCTAssertEqual(parse("alive://random"), .random)
        XCTAssertEqual(parse("alive://rescan"), .rescan)
        XCTAssertEqual(parse("alive://stat"), .stat)
        XCTAssertEqual(parse("ALIVE://HOME"), .home)
    }

    func testQueriesAreDecoded() {
        XCTAssertEqual(parse("alive://sets?q=dark%20techno"), .sets(query: "dark techno"))
        XCTAssertEqual(parse("alive://sets"), .sets(query: ""))
        XCTAssertEqual(parse("alive://samples?q=kick"), .samples(query: "kick"))
        XCTAssertEqual(parse("alive://sets?q=%E3%83%86%E3%82%B9%E3%83%88"), .sets(query: "テスト"))
    }

    func testOpenNeedsAPath() {
        XCTAssertEqual(parse("alive://open?path=/Music/A%20Project/a.als"), .open(path: "/Music/A Project/a.als"))
        XCTAssertNil(parse("alive://open"))
        XCTAssertNil(parse("alive://open?path="))
    }

    func testRejectsOtherSchemesAndUnknownCommands() {
        XCTAssertNil(parse("http://home"))
        XCTAssertNil(parse("alive://delete?path=/x"))
        XCTAssertNil(parse("alive:///home"))
        XCTAssertNil(parse("alive:home"))
    }

    func testOnlySetDependentCommandsWaitForTheCatalog() {
        XCTAssertTrue(URLCommand.open(path: "/x").needsCatalog)
        XCTAssertTrue(URLCommand.latest.needsCatalog)
        XCTAssertTrue(URLCommand.random.needsCatalog)
        XCTAssertFalse(URLCommand.home.needsCatalog)
        XCTAssertFalse(URLCommand.rescan.needsCatalog)
    }
}

final class URLCommandPlanTests: XCTestCase {
    private func entry(_ path: String, modified: TimeInterval, backup: Bool = false) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.modified = Date(timeIntervalSince1970: modified)
        e.isBackup = backup
        return e
    }

    private var sets: [SetEntry] {
        [entry("/Music/A Project/a.als", modified: 100),
         entry("/Music/B Project/b.als", modified: 300),
         entry("/Music/C Project/Backup/c [2026-01-01].als", modified: 900, backup: true),
         entry("/Music/D Project/d.als", modified: 200)]
    }

    func testNonSetCommandsMapDirectly() {
        XCTAssertEqual(URLCommands.plan(.home, sets: []), .showHome)
        XCTAssertEqual(URLCommands.plan(.sets(query: "x"), sets: []), .showSets(query: "x"))
        XCTAssertEqual(URLCommands.plan(.samples(query: "y"), sets: []), .showSamples(query: "y"))
        XCTAssertEqual(URLCommands.plan(.rescan, sets: []), .rescan)
        XCTAssertEqual(URLCommands.plan(.stat, sets: []), .showStat)
    }

    func testOpenSelectsAndOpensAKnownSet() {
        XCTAssertEqual(URLCommands.plan(.open(path: "/Music/A Project/a.als"), sets: sets),
                       .select(path: "/Music/A Project/a.als", openInLive: true))
    }

    func testOpenResolvesDotDotAndCaseButOpensTheCatalogsPath() {
        XCTAssertEqual(URLCommands.plan(.open(path: "/Music/B Project/../A Project/a.als"), sets: sets),
                       .select(path: "/Music/A Project/a.als", openInLive: true))
        XCTAssertEqual(URLCommands.plan(.open(path: "/music/a project/A.ALS"), sets: sets),
                       .select(path: "/Music/A Project/a.als", openInLive: true))
    }

    func testOpenRefusesAnythingOutsideTheCatalog() {
        for path in ["/etc/passwd", "/Music/Z Project/z.als", "relative/a.als", "/Music/A Project/", "~/a.als"] {
            XCTAssertEqual(URLCommands.plan(.open(path: path), sets: sets), .refuse(.notInCatalog(path)), path)
        }
    }

    func testOpenDoesNotAcceptBackupCopies() {
        let backup = "/Music/C Project/Backup/c [2026-01-01].als"
        XCTAssertEqual(URLCommands.plan(.open(path: backup), sets: sets), .refuse(.notInCatalog(backup)))
    }

    func testLatestIsTheNewestRealSet() {
        XCTAssertEqual(URLCommands.plan(.latest, sets: sets), .select(path: "/Music/B Project/b.als", openInLive: true))
    }

    func testRandomPicksThroughTheGivenIndexAndOnlyRealSets() {
        var asked = 0
        let action = URLCommands.plan(.random, sets: sets) { count in asked = count; return 1 }
        XCTAssertEqual(asked, 3)
        XCTAssertEqual(action, .select(path: "/Music/B Project/b.als", openInLive: false))
        // An out-of-range pick is clamped rather than crashing.
        XCTAssertEqual(URLCommands.plan(.random, sets: sets) { _ in 99 },
                       .select(path: "/Music/D Project/d.als", openInLive: false))
    }

    func testEmptyCatalogRefusesSetCommands() {
        XCTAssertEqual(URLCommands.plan(.latest, sets: []), .refuse(.emptyCatalog))
        XCTAssertEqual(URLCommands.plan(.random, sets: []), .refuse(.emptyCatalog))
        XCTAssertEqual(URLCommands.plan(.latest, sets: [entry("/a/b.als", modified: 1, backup: true)]), .refuse(.emptyCatalog))
    }
}

@MainActor
final class URLCommandPerformTests: XCTestCase {
    func testSelectShowsTheSetOnTheSetsTab() throws {
        let app = try makeModel()
        app.tab = .home
        app.searchText = "left over"
        URLCommands.perform(.select(path: "/Music/A Project/a.als", openInLive: false), on: app)
        XCTAssertEqual(app.tab, .sets)
        XCTAssertEqual(app.selectedSetPath, "/Music/A Project/a.als")
        XCTAssertEqual(app.searchText, "")
    }

    func testSetsAndSamplesSetTheSearch() throws {
        let app = try makeModel()
        URLCommands.perform(.showSets(query: "techno"), on: app)
        XCTAssertEqual(app.tab, .sets)
        XCTAssertEqual(app.searchText, "techno")
        URLCommands.perform(.showSamples(query: "kick"), on: app)
        XCTAssertEqual(app.tab, .samples)
        XCTAssertEqual(app.searchText, "kick")
        URLCommands.perform(.showHome, on: app)
        XCTAssertEqual(app.tab, .home)
    }

    func testRefusalShowsAToast() throws {
        let app = try makeModel()
        URLCommands.perform(.refuse(.notInCatalog("/etc/passwd")), on: app)
        XCTAssertEqual(app.toasts.count, 1)
        XCTAssertTrue(app.toasts[0].text.contains("/etc/passwd"))
    }
}

final class WidgetSnapshotWriterTests: XCTestCase {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "alive-widget-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func snapshot(streak: Int, at: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: at, currentStreak: streak, longestStreak: 9, activeDays: 12,
                       lastActiveDay: Calendar.current.startOfDay(for: at), days: [], recent: [])
    }

    func testWritesThenSkipsAnUnchangedSnapshotThenWritesAChangedOne() throws {
        let dir = try scratch()
        let now = Date()
        XCTAssertEqual(WidgetSnapshotWriter.write(snapshot(streak: 3, at: now), dir: dir), .written)
        let url = WidgetSnapshot.appFileURL(dataDir: dir)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "widget")
        XCTAssertEqual(WidgetSnapshot.load(from: url)?.currentStreak, 3)
        XCTAssertEqual(WidgetSnapshotWriter.write(snapshot(streak: 3, at: now.addingTimeInterval(600)), dir: dir), .unchanged)
        XCTAssertEqual(WidgetSnapshotWriter.write(snapshot(streak: 4, at: now), dir: dir), .written)
        XCTAssertEqual(WidgetSnapshot.load(from: url)?.currentStreak, 4)
    }

    func testTheOldTopLevelFileIsRemoved() throws {
        let dir = try scratch()
        let legacy = AppHome.file(WidgetSnapshot.fileName, in: dir)
        try AppHome.writeAtomically("{}", to: legacy)
        WidgetSnapshotWriter.write(snapshot(streak: 1), dir: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy))
        XCTAssertTrue(FileManager.default.fileExists(atPath: WidgetSnapshot.appFileURL(dataDir: dir).path))
    }

    func testCreatesTheFolderAndReportsAnUnwritableOne() throws {
        let dir = try scratch() + "/not/yet/there"
        XCTAssertEqual(WidgetSnapshotWriter.write(snapshot(streak: 1), dir: dir), .written)
        guard case .failed = WidgetSnapshotWriter.write(snapshot(streak: 2), dir: "/dev/null/x") else {
            return XCTFail("writing under /dev/null must fail")
        }
    }
}

final class ExtensionsTests: XCTestCase {
    func testStringTableIsComplete() {
        assertStringTableIsComplete(ExtensionStrings.self)
    }

    func testPluginkitOutputParsing() {
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "+    io.github.x.quicklook(0.2.1)\n"), .enabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "-    io.github.x.quicklook(0.2.1)\n"), .disabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "     io.github.x.quicklook(0.2.1)\n"), .disabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "!    io.github.x.quicklook(0.2.1)\n"), .disabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: ""), .notInstalled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "\n  \n"), .notInstalled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "(no matches)\n"), .notInstalled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: "  (no matches)\n"), .notInstalled)
    }

    func testEnabledCopyIsFoundAfterOtherRegisteredCopies() {
        let superseded = "!    io.github.x.quicklook(0.2.1)\n"
        let disabled = "-    io.github.x.quicklook(0.3.0)\n"
        let enabled = "+    io.github.x.quicklook(0.3.0)\n"
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: superseded + enabled), .enabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: disabled + enabled), .enabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: enabled + superseded), .enabled)
        XCTAssertEqual(ExtensionState.parse(pluginkitOutput: superseded + disabled), .disabled)
    }

    func testQueryFailureDoesNotClaimTheExtensionIsAbsentOrDisabled() {
        XCTAssertEqual(PluginKit.state(from: .init(status: -1, output: "")), .checkFailed)
        XCTAssertEqual(PluginKit.state(from: .init(status: 1, output: "permission denied")), .checkFailed)
        XCTAssertEqual(PluginKit.state(from: .init(status: 1, output: "+ io.github.x.quicklook(0.3.0)")), .checkFailed)
        XCTAssertEqual(PluginKit.state(from: .init(status: 0, output: "")), .notInstalled)
        XCTAssertEqual(PluginKit.state(from: .init(status: 0, output: "+ io.github.x.quicklook(0.3.0)")), .enabled)
    }

    func testBundleIdentifiersMatchThePackagedExtensions() {
        XCTAssertEqual(AppExtension.quickLook.bundleID, "io.github.bassmicrobe.alive-for-mac.quicklook")
        XCTAssertEqual(AppExtension.widget.bundleID, "io.github.bassmicrobe.alive-for-mac.widget")
    }
}
