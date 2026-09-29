import XCTest
@testable import AliveCore
@testable import AliveUI

@MainActor
final class PluginsModelTests: XCTestCase {
    private func set(_ name: String, _ plugins: [(String, String)], modified: TimeInterval) -> SetEntry {
        var e = SetEntry()
        e.path = "/music/\(name).als"
        e.name = name
        e.modified = Date(timeIntervalSince1970: modified)
        e.plugins = plugins.map(\.0)
        e.pluginUids = plugins.map(\.1)
        e.pluginVendors = plugins.map { _ in "" }
        e.pluginVendorConfident = plugins.map { _ in false }
        return e
    }

    private func installed(_ uid: String, _ name: String, vendor: String = "", category: String = "") -> InstalledPlugin {
        var p = InstalledPlugin()
        p.uid = uid; p.name = name; p.vendor = vendor; p.category = category; p.path = "/plugins/\(name).vst3"
        return p
    }

    /// An app whose catalog holds three sets and whose machine has Serum, Pro-Q and an idle plugin.
    private func makeApp(inventory: [InstalledPlugin]?) throws -> AppModel {
        let app = try makeModel()
        let index = app.catalog.index
        index.lock.lock()
        index._sets = [
            set("a", [("Serum", "vst3:s"), ("Pro-Q", "vst3:q")], modified: 300),
            set("b", [("Serum", "vst3:s"), ("Ghost", "vst2:9")], modified: 100),
            set("c", [("Pro-Q", "vst3:q")], modified: 200),
        ]
        index._generation += 1
        index.lock.unlock()
        var inv = PluginInventory()
        for p in inventory ?? [] { inv.add(p) }
        let frozen = inv
        index.inventoryLoader = { _ in frozen }
        index.refreshInstalled()
        app.catalog.settingsDidChange()                     // bumps `revision`: the model re-reads
        return app
    }

    private var standardMachine: [InstalledPlugin] {
        [installed("vst3:s", "Serum", vendor: "Xfer", category: "Instrument|Synth"),
         installed("vst3:q", "Pro-Q", vendor: "FabFilter", category: "Fx|EQ"),
         installed("vst3:idle", "Idle One", vendor: "Nobody", category: "Fx|Reverb")]
    }

    func testRowsAreTheCatalogsPluginsAndShownCountFollowsSearch() throws {
        let app = try makeApp(inventory: standardMachine)
        XCTAssertEqual(app.plugins.rows.map(\.name), ["Pro-Q", "Serum", "Ghost", "Idle One"])   // most used first, then name
        XCTAssertEqual(app.plugins.shownCount, 4)
        XCTAssertEqual(app.shownCount, 0, "the toolbar follows the active tab")
        app.tab = .plugins
        XCTAssertEqual(app.shownCount, 4)
        app.searchText = "fabfilter"
        XCTAssertEqual(app.plugins.rows.map(\.name), ["Pro-Q"])
        XCTAssertEqual(app.shownCount, 1)
        app.searchText = ""
    }

    func testSortingToggles() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        m.toggleSort(.name)
        XCTAssertEqual(m.rows.map(\.name), ["Ghost", "Idle One", "Pro-Q", "Serum"])
        m.toggleSort(.name)
        XCTAssertEqual(m.rows.map(\.name), ["Serum", "Pro-Q", "Idle One", "Ghost"])
        m.toggleSort(.name)                                  // third click: back to the catalog's order
        XCTAssertNil(m.sortColumn)
        XCTAssertEqual(m.rows.first?.name, "Pro-Q")
        m.toggleSort(.sets)
        XCTAssertFalse(m.sortAscending, "counts read best biggest first")
        m.toggleSort(.vendor)
        XCTAssertTrue(m.sortAscending)
    }

    func testCardsAndFiltersNarrowTheRows() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        m.toggleCard(.missing)
        XCTAssertEqual(m.rows.map(\.name), ["Ghost"])
        m.toggleCard(.missing)
        XCTAssertNil(m.card)
        m.filter.vendors = ["Xfer"]
        XCTAssertEqual(m.rows.map(\.name), ["Serum"])
        XCTAssertTrue(m.filtersActive)
        m.resetFilters()
        XCTAssertFalse(m.filtersActive)
        XCTAssertEqual(m.rows.count, 4)
    }

    func testSelectionAndTheSetsThatUseThePlugin() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        XCTAssertNil(m.selectedRow)
        m.moveSelection(by: 1)
        XCTAssertEqual(m.selectedRow?.name, "Pro-Q")
        XCTAssertEqual(m.pendingScrollID, m.selectedID)
        XCTAssertEqual(m.selectedSets.map(\.name), ["a", "c"])
        m.moveSelection(by: 1)
        XCTAssertEqual(m.selectedRow?.name, "Serum")
        m.moveSelection(by: nil, toEnd: true)
        XCTAssertEqual(m.selectedRow?.name, "Idle One")
        m.moveSelection(by: 5)
        XCTAssertEqual(m.selectedRow?.name, "Idle One", "clamped at the end")
        m.moveSelection(by: nil)
        XCTAssertEqual(m.selectedRow?.name, "Pro-Q")
        m.moveSelection(by: -1)
        XCTAssertEqual(m.selectedRow?.name, "Pro-Q", "clamped at the start")
    }

    func testShowPluginNamedSelectsItAndClearsWhatWouldHideIt() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        app.tab = .sets
        app.searchText = "zzz"
        m.toggleCard(.unused)
        m.filter.vendors = ["Nobody"]
        m.show(pluginNamed: "serum")
        XCTAssertEqual(app.tab, .plugins)
        XCTAssertEqual(app.searchText, "")
        XCTAssertNil(m.card)
        XCTAssertTrue(m.filter.isEmpty, "the filter hid it, so it goes")
        XCTAssertEqual(m.selectedRow?.name, "Serum")
        XCTAssertEqual(m.pendingScrollID, m.selectedID)
        // An unknown name only switches the tab.
        m.selectedID = nil
        m.show(pluginNamed: "nothing at all")
        XCTAssertNil(m.selectedRow)
        m.show(pluginNamed: "")
        XCTAssertEqual(app.tab, .plugins)
    }

    func testShowPluginKeepsAFilterThatStillMatches() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        m.filter.vendors = ["Xfer"]
        m.show(pluginNamed: "Serum")
        XCTAssertEqual(m.filter.vendors, ["Xfer"])
    }

    func testOpeningASetGoesToTheSetsTab() throws {
        let app = try makeApp(inventory: standardMachine)
        app.tab = .plugins
        app.searchText = "serum"
        app.plugins.openSet(path: "/music/a.als")
        XCTAssertEqual(app.tab, .sets)
        XCTAssertEqual(app.selectedSetPath, "/music/a.als")
        XCTAssertEqual(app.searchText, "")
    }

    func testMissingIsOneNumberAndAnUnavailableInventoryIsCalm() throws {
        let app = try makeApp(inventory: standardMachine)
        XCTAssertTrue(app.plugins.inventoryAvailable)
        XCTAssertEqual(app.plugins.missingUsedCount, 1)

        let blind = try makeApp(inventory: nil)
        XCTAssertFalse(blind.plugins.inventoryAvailable)
        XCTAssertEqual(blind.plugins.missingUsedCount, 0)
        XCTAssertEqual(blind.plugins.rows.count, 3)
        XCTAssertTrue(blind.plugins.rows.allSatisfy { $0.status == .unknown })
        XCTAssertTrue(blind.toasts.isEmpty, "no toast for an unreadable inventory")
    }

    func testRevealOfAMissingFileToastsOnceAndDoesNothingWithoutAPath() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        let ghost = try XCTUnwrap(m.table.row(named: "Ghost"))
        m.reveal(ghost)                                       // no path: silent
        XCTAssertTrue(app.toasts.isEmpty)
        let serum = try XCTUnwrap(m.table.row(named: "Serum"))
        m.reveal(serum)                                       // /plugins/Serum.vst3 does not exist
        XCTAssertEqual(app.toasts.count, 1)
    }

    func testFacetsFollowTheFilter() throws {
        let app = try makeApp(inventory: standardMachine)
        let m = app.plugins
        XCTAssertEqual(m.facets.matches, 4)
        m.filter.statusMissing = true
        XCTAssertEqual(m.facets.matches, 1)
        XCTAssertEqual(m.facets.installed, 3)
    }
}
