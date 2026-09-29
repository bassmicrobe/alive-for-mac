import XCTest
import AliveCore
@testable import AliveUI

private func entry(_ path: String, name: String? = nil, project: String = "", modified: Double = 0) -> SetEntry {
    var e = SetEntry()
    e.path = path
    e.name = name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    e.projectName = project
    e.modified = Date(timeIntervalSince1970: modified)
    return e
}

private func scratchDir() throws -> String {
    let dir = NSTemporaryDirectory() + "alive-ui-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - Settings <-> preferences

@MainActor
final class PreferencesMappingTests: XCTestCase {
    private var savedLanguage: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        savedLanguage = Localizer.shared.preference
    }

    override func tearDown() {
        Localizer.shared.preference = savedLanguage
        super.tearDown()
    }

    func testLoadsPreferencesFromSettingsFile() throws {
        let app = try makeModel(files: ["settings.cfg": "noglass=0\ncheckupdates=1\npluginfolders=1\nlang=ja\n"])
        XCTAssertTrue(app.prefs.transparency)
        XCTAssertTrue(app.prefs.dailyUpdateCheck)
        XCTAssertEqual(app.prefs.pluginSource, .pluginFolders)
        XCTAssertEqual(app.prefs.language, .ja)
        XCTAssertEqual(Localizer.shared.preference, .ja, "the localizer starts from settings.lang")
    }

    func testDefaultsMatchUpstream() throws {
        let app = try makeModel()
        XCTAssertFalse(app.prefs.transparency, "glass is off by default (noglass=1)")
        XCTAssertFalse(app.prefs.dailyUpdateCheck)
        XCTAssertEqual(app.prefs.pluginSource, .liveDatabase)
        XCTAssertEqual(app.prefs.language, .system)
    }

    func testChangesAreWrittenToSettingsFile() throws {
        let app = try makeModel()
        app.prefs.transparency = true
        app.prefs.dailyUpdateCheck = true
        app.prefs.language = .en
        let reloaded = AppSettings.load(dir: app.dataDir)
        XCTAssertFalse(reloaded.disableGlass)
        XCTAssertTrue(reloaded.checkUpdates)
        XCTAssertEqual(reloaded.lang, "en")
        XCTAssertEqual(Localizer.shared.preference, .en)
    }

    func testUnknownKeysSurviveASave() throws {
        let app = try makeModel(files: ["settings.cfg": "futurekey=42\n"])
        app.prefs.language = .ja
        let text = try String(contentsOfFile: AppSettings.filePath(dir: app.dataDir), encoding: .utf8)
        XCTAssertTrue(text.contains("futurekey=42"))
        XCTAssertTrue(text.contains("lang=ja"))
    }

    func testUnchangedValueDoesNotWrite() throws {
        let app = try makeModel()
        app.prefs.transparency = false
        XCTAssertFalse(FileManager.default.fileExists(atPath: AppSettings.filePath(dir: app.dataDir)))
    }

    func testSaveFailureIsShownAsToast() throws {
        let app = try makeModel()
        // A file where the data folder should be: the atomic write cannot succeed.
        try FileManager.default.removeItem(atPath: app.dataDir)
        FileManager.default.createFile(atPath: app.dataDir, contents: Data())
        app.prefs.dailyUpdateCheck = true
        XCTAssertEqual(app.toasts.count, 1)
        XCTAssertEqual(app.toasts.first?.kind, .error)
    }
}

// MARK: - Search

final class SetSearchTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SetSearch.matches(entry("/a/x.als"), query: "  "))
    }

    func testCaseAndDiacriticsAreIgnored() {
        let set = entry("/a/Café Mix.als", project: "Sommer")
        XCTAssertTrue(SetSearch.matches(set, query: "cafe"))
        XCTAssertTrue(SetSearch.matches(set, query: "MIX"))
        XCTAssertTrue(SetSearch.matches(set, query: "sommer"))
        XCTAssertFalse(SetSearch.matches(set, query: "winter"))
    }

    func testFullWidthLettersMatchHalfWidth() {
        XCTAssertTrue(SetSearch.matches(entry("/a/Mix.als"), query: "ｍｉｘ"))
    }

    func testEveryWordMustMatchNameOrProject() {
        let set = entry("/a/Song.als", project: "Album")
        XCTAssertTrue(SetSearch.matches(set, query: "song album"))
        XCTAssertFalse(SetSearch.matches(set, query: "song single"))
    }

    func testFilterRunsBeforeFoldingByFolder() {
        let sets = [entry("/p/v1.als", modified: 1), entry("/p/final.als", modified: 2), entry("/q/other.als")]
        // "v1" only exists in the older version: folding first would have hidden it.
        let rows = SetSearch.rows(sets, query: "v1", groupByFolder: true)
        XCTAssertEqual(rows.map(\.path), ["/p/v1.als"])
        let all = SetSearch.rows(sets, query: "", groupByFolder: true)
        XCTAssertEqual(Set(all.map(\.path)), ["/p/final.als", "/q/other.als"])
        XCTAssertEqual(all.first { $0.path == "/p/final.als" }?.collapsedCount, 1)
        XCTAssertEqual(SetSearch.rows(sets, query: "", groupByFolder: false).count, 3)
    }
}

// MARK: - Open-path resolution

final class OpenPathPlanTests: XCTestCase {
    private let sets = [entry("/Music/Proj/A Project/a.als"), entry("/Music/Proj/B Project/b.als")]

    func testKnownSetIsSelectedWithTheCatalogsSpelling() {
        let plan = OpenPathPlan.make(paths: ["/music/proj/a project/A.als"], sets: sets,
                                     roots: ["/Music/Proj"], disabledRoots: [], fileExists: { _ in true })
        XCTAssertEqual(plan.select, ["/Music/Proj/A Project/a.als"])
        XCTAssertTrue(plan.addRoots.isEmpty)
    }

    func testUnknownSetOutsideRootsAddsItsFolder() {
        let plan = OpenPathPlan.make(paths: ["/Elsewhere/X/x.als", "/Elsewhere/X/y.als"], sets: sets,
                                     roots: ["/Music/Proj"], disabledRoots: [], fileExists: { _ in true })
        XCTAssertEqual(plan.addRoots, ["/Elsewhere/X"], "one folder, no repeats")
        XCTAssertTrue(plan.select.isEmpty)
    }

    func testUnknownSetInsideAScannedRootJustOpens() {
        let plan = OpenPathPlan.make(paths: ["/Music/Proj/A Project/Backup/old.als"], sets: sets,
                                     roots: ["/Music/Proj"], disabledRoots: [], fileExists: { _ in true })
        XCTAssertEqual(plan.openDirectly, ["/Music/Proj/A Project/Backup/old.als"])
        XCTAssertTrue(plan.addRoots.isEmpty)
    }

    func testDisabledRootDoesNotCover() {
        let plan = OpenPathPlan.make(paths: ["/Music/Proj/c.als"], sets: sets,
                                     roots: ["/Music/Proj"], disabledRoots: ["/Music/Proj"], fileExists: { _ in true })
        XCTAssertTrue(plan.addRoots.isEmpty, "the root is already in the list, only switched off")
        XCTAssertTrue(plan.openDirectly.isEmpty)
    }

    func testMissingFilesAreSkipped() {
        let plan = OpenPathPlan.make(paths: ["/gone/x.als", ""], sets: sets, roots: [], disabledRoots: [],
                                     fileExists: { _ in false })
        XCTAssertEqual(plan, OpenPathPlan())
    }
}

@MainActor
final class OpenPathFlowTests: XCTestCase {
    func testPathsWaitForTheCatalogAndAreKept() throws {
        let app = try makeModel()
        app.openPaths(["/a.als"])
        XCTAssertEqual(app.pendingOpenPaths, ["/a.als"], "catalog not loaded yet: nothing is consumed")
        XCTAssertEqual(app.tab, .home)
    }
}

// MARK: - Root suggestions

final class RootSuggestionsTests: XCTestCase {
    func testSuggestsExistingFoldersOnceAndSkipsScannedOnes() throws {
        let home = try scratchDir()
        let ableton = home + "/Music/Ableton"
        let places = home + "/Places/Projects"
        for dir in [ableton, ableton + "/User Library", places] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        var env = LiveEnvironment()
        env.userLibrary = ableton + "/User Library"
        env.places = [LivePlace(name: "Projects", path: places), LivePlace(name: "Gone", path: home + "/nowhere")]

        let all = RootSuggestions.make(env: env, existingRoots: [], home: home)
        XCTAssertEqual(all.map(\.path), [ableton, places], "~/Music/Ableton and the User Library parent are one")

        let covered = RootSuggestions.make(env: env, existingRoots: [home + "/Music"], home: home)
        XCTAssertEqual(covered.map(\.path), [places])
    }

    func testDisplayAbbreviatesHome() {
        XCTAssertEqual(RootSuggestion(path: "/Users/x/Music/Ableton").display(home: "/Users/x"), "~/Music/Ableton")
        XCTAssertEqual(RootSuggestion(path: "/Volumes/D/Live").display(home: "/Users/x"), "/Volumes/D/Live")
    }
}

// MARK: - Root edits

@MainActor
final class CatalogRootsTests: XCTestCase {
    func testAddRemoveAndDisableRootsPersist() throws {
        let app = try makeModel()
        let folder = try scratchDir()
        XCTAssertEqual(app.catalog.addRoots([folder]).count, 1)
        XCTAssertEqual(AppSettings.load(dir: app.dataDir).roots, [folder])
        XCTAssertTrue(app.catalog.hasEnabledRoots)

        XCTAssertTrue(app.catalog.addRoots([folder]).isEmpty, "the same folder twice is one root")
        XCTAssertEqual(app.settings.roots.count, 1)

        app.catalog.setRoot(folder, enabled: false)
        XCTAssertEqual(AppSettings.load(dir: app.dataDir).disabledRoots, [folder])
        XCTAssertFalse(app.catalog.hasEnabledRoots)

        app.catalog.setRoot(folder, enabled: true)
        XCTAssertTrue(app.catalog.hasEnabledRoots)

        app.catalog.removeRoot(folder)
        XCTAssertTrue(AppSettings.load(dir: app.dataDir).roots.isEmpty)
    }

    func testAFileCountsAsItsFolderAndMissingPathsToastAnError() throws {
        let app = try makeModel()
        let folder = try scratchDir()
        let file = folder + "/x.als"
        FileManager.default.createFile(atPath: file, contents: Data())
        XCTAssertEqual(app.catalog.addRoots([file]), [(folder as NSString).standardizingPath])
        app.toasts.removeAll()
        XCTAssertTrue(app.catalog.addRoots([folder + "/missing"]).isEmpty)
        XCTAssertEqual(app.toasts.first?.kind, .error)
    }
}

// MARK: - Misc

final class SetFormatTests: XCTestCase {
    func testTempoAndCounts() {
        XCTAssertEqual(SetFormat.tempo(128), "128")
        XCTAssertEqual(SetFormat.tempo(127.5), "127.5")
        XCTAssertEqual(SetFormat.tempo(0), "")
        XCTAssertEqual(SetFormat.count(0), "")
        XCTAssertEqual(SetFormat.count(12), "12")
        XCTAssertEqual(SetFormat.size(0), "")
    }

    func testModifiedFollowsTheLocale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotEqual(SetFormat.modified(date, locale: Locale(identifier: "en_US")),
                          SetFormat.modified(date, locale: Locale(identifier: "ja_JP")))
        XCTAssertEqual(SetFormat.modified(.distantPast), "")
    }
}

@MainActor
final class LiveLauncherTests: XCTestCase {
    func testNewestFirstSortsByCoreVersionAndDropsRepeats() {
        func app(_ path: String, _ v: String) -> LiveApp {
            LiveApp(url: URL(fileURLWithPath: path), version: LiveVersion(v)!)
        }
        let sorted = LiveLauncher.newestFirst([
            app("/Applications/Live 11.app", "11.3.20"),
            app("/Applications/Live 12 Beta.app", "12.0b20"),
            app("/Applications/Live 12.app", "12.0"),
            app("/Applications/Live 12.app", "12.0"),
        ])
        XCTAssertEqual(sorted.map(\.url.lastPathComponent), ["Live 12.app", "Live 12 Beta.app", "Live 11.app"])
    }
}
