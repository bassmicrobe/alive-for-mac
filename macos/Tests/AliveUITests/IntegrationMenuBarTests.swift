import XCTest
import AppKit
import SwiftUI
import AliveCore
@testable import AliveUI

@MainActor
final class IntegrationMenuBarTests: XCTestCase {
    private static let off = "spotlight=0\nmenubar=0\nfindertags=0\n"

    private func set(_ path: String, modified: Double, backup: Bool = false) -> SetEntry {
        var e = SetEntry()
        e.path = path; e.name = (path as NSString).lastPathComponent; e.isBackup = backup
        e.modified = Date(timeIntervalSince1970: modified)
        return e
    }

    func testRecentIsOnePerProjectNewestFirstAndCapped() {
        var sets = (0..<12).map { set("/lib/P\($0)/a.als", modified: Double($0 + 10)) }
        sets.append(set("/lib/P11/older.als", modified: 1))
        sets.append(set("/lib/P5/Backup/b.als", modified: 999, backup: true))
        let snap = MenuBarSnapshot.make(sets: sets, pins: [], activity: .empty)
        XCTAssertEqual(snap.recent.count, MenuBarSnapshot.recentLimit)
        XCTAssertEqual(snap.recent.first?.path, "/lib/P11/a.als")
        XCTAssertEqual(Set(snap.recent.map(\.projectDir)).count, snap.recent.count)
        XCTAssertFalse(snap.recent.contains { $0.isBackup })
        XCTAssertEqual(snap.savesToday, 0)
        XCTAssertEqual(snap.streak, 0)
    }

    func testPinnedKeepsPinsOnlyNewestFirst() {
        let sets = [set("/a/x.als", modified: 1), set("/b/y.als", modified: 3), set("/c/z.als", modified: 2)]
        let snap = MenuBarSnapshot.make(sets: sets, pins: ["/a/x.als", "/b/y.als", "/nope.als"], activity: .empty)
        XCTAssertEqual(snap.pinned.map(\.path), ["/b/y.als", "/a/x.als"])
    }

    func testManyPinsKeepTheProjectListBoundedWhileShortListsStayCompact() throws {
        let app = try makeModel(files: ["settings.cfg": Self.off])
        let sets = (0..<40).map { set("/lib/P\($0)/a.als", modified: Double($0)) }
        let long = MenuBarSnapshot.make(sets: sets, pins: Set(sets.map(\.path)), activity: .empty)
        let short = MenuBarSnapshot.make(sets: Array(sets.prefix(1)), pins: [], activity: .empty)
        let longHost = NSHostingView(rootView: MenuBarProjects(snapshot: long).environment(app).frame(width: 302))
        let shortHost = NSHostingView(rootView: MenuBarProjects(snapshot: short).environment(app).frame(width: 302))
        longHost.layoutSubtreeIfNeeded()
        shortHost.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(longHost.fittingSize.height, 0)
        XCTAssertLessThanOrEqual(longHost.fittingSize.height, MenuBarProjects.maxHeight + 1)
        XCTAssertLessThan(shortHost.fittingSize.height, longHost.fittingSize.height)
        XCTAssertEqual(long.pinned.count, 40) // Every pin remains available in the scrolling list.
    }

    func testPreferencesRoundTripThroughTheModel() throws {
        let app = try makeModel(files: ["settings.cfg": Self.off])
        XCTAssertFalse(app.prefs.spotlight)
        XCTAssertFalse(app.prefs.menuBar)
        XCTAssertFalse(app.prefs.finderTags)
        app.prefs.menuBar = true
        app.prefs.finderTags = true
        let saved = try String(contentsOfFile: app.dataDir + "/settings.cfg", encoding: .utf8)
        XCTAssertTrue(saved.contains("menubar=1"))
        XCTAssertTrue(saved.contains("findertags=1"))
        XCTAssertTrue(saved.contains("spotlight=0"))
    }

    func testShowInAliveWaitsForTheCatalogAndReportsAMissingSet() throws {
        let app = try makeModel(files: ["settings.cfg": Self.off])
        var shown = 0
        app.integration.presentWindow = { shown += 1 }
        app.integration.showInAlive(path: "/nowhere.als")   // catalog not ready: waits
        XCTAssertEqual(shown, 1)
        XCTAssertEqual(app.tab, .home)
        XCTAssertNil(app.selectedSetPath)
    }
}
