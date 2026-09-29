// Mac-only: Plugins tab state (upstream: the plugin parts of MainForm.cs — FillPlugins, the summary
// cards, SelectedPlugin, OnPluginRequested). Everything a list shows is derived from the catalog
// snapshot and memoized on `catalog.revision`.
import AppKit
import Foundation
import Observation
import AliveCore

@MainActor
@Observable
final class PluginsModel {
    @ObservationIgnored unowned let app: AppModel

    /// The summary card that acts as a filter; nil: none.
    var card: PluginCard?
    var filter = PluginFilter()
    /// nil: the catalog's own order (most used first).
    var sortColumn: PluginColumn?
    var sortAscending = true
    var selectedID: String?
    /// Set by `show(pluginNamed:)`; the list scrolls to it once it exists and clears it.
    var pendingScrollID: String?

    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private var rowsMemo: (key: String, rows: [PluginRow])?

    init(app: AppModel) {
        self.app = app
    }

    /// Everything derived from one catalog revision.
    private struct Snapshot {
        let revision: Int
        let table: PluginTable
        let health: PluginHealth
        let available: Bool
        let stats: [PluginStat]
    }

    private var current: Snapshot {
        let revision = app.catalog.revision
        if let snapshot, snapshot.revision == revision { return snapshot }
        let index = app.catalog.index
        let usage = index.pluginUsage()
        let made = Snapshot(revision: revision, table: PluginTable(usage: usage, sets: index.sets),
                            health: index.health(usage), available: index.inventory.isAvailable, stats: usage)
        snapshot = made
        return made
    }

    // MARK: - What the views read

    var table: PluginTable { current.table }
    var health: PluginHealth { current.health }
    /// False when the machine's plugins could not be read: nothing is then called "missing".
    var inventoryAvailable: Bool { current.available }
    var allStats: [PluginStat] { current.stats }
    var facets: PluginFacets { PluginFacets.compute(filter, over: current.stats) }

    /// How many plugins used in sets are not installed (one number, never one message each).
    var missingUsedCount: Int { current.available ? current.health.missing : 0 }

    var hasCatalogPlugins: Bool { !current.table.rows.isEmpty }

    /// The rows the list shows: search, summary card and filters, then the chosen order.
    var rows: [PluginRow] {
        let words = SetSearch.words(in: app.searchText)
        let key = "\(app.catalog.revision)|\(app.searchText)|\(card.map { "\($0.rawValue)" } ?? "-")|\(filter.hashValue)"
            + "|\(sortColumn?.rawValue ?? "-")|\(sortAscending)"
        if let rowsMemo, rowsMemo.key == key { return rowsMemo.rows }
        var list = current.table.rows.filter { row in
            (card?.passes(row.stat) ?? true) && filter.matches(row.stat) && row.matches(search: words)
        }
        if let sortColumn {
            list.sort(using: PluginSort(sortColumn, order: sortAscending ? .forward : .reverse))
        }
        rowsMemo = (key, list)
        return list
    }

    /// The toolbar's "N shown".
    var shownCount: Int { rows.count }

    var selectedRow: PluginRow? {
        guard let selectedID else { return nil }
        return current.table.rows.first { $0.id == selectedID }
    }

    var filtersActive: Bool { !filter.isEmpty }

    /// The sets that use the selected plugin, newest first.
    var selectedSets: [SetEntry] {
        guard let row = selectedRow else { return [] }
        return current.table.sets(using: row.name)
    }

    // MARK: - Actions

    func toggleSort(_ column: PluginColumn) {
        if sortColumn == column {
            if sortAscending { sortAscending = false } else { sortColumn = nil; sortAscending = true }
        } else {
            sortColumn = column
            // Numbers and dates read best biggest / newest first, like upstream's default order.
            sortAscending = ![.sets, .lastUsed].contains(column)
        }
    }

    func toggleCard(_ picked: PluginCard) {
        card = card == picked ? nil : picked
    }

    func resetFilters() {
        filter.clear()
        card = nil
    }

    /// Up/down/home/end in the list.
    func moveSelection(by step: Int?, toEnd: Bool = false) {
        let list = rows
        guard !list.isEmpty else { return }
        let at = list.firstIndex { $0.id == selectedID }
        let target: Int
        if let step {
            target = min(max((at ?? (step > 0 ? -1 : list.count)) + step, 0), list.count - 1)
        } else {
            target = toEnd ? list.count - 1 : 0
        }
        selectedID = list[target].id
        pendingScrollID = selectedID
    }

    /// Opens the Plugins tab on one plugin (from a set's plugin list in the Sets inspector).
    /// Cross-feature entry point: keep this signature.
    func show(pluginNamed name: String) {
        app.tab = .plugins
        guard !name.isEmpty else { return }
        app.searchText = ""
        card = nil
        guard let row = current.table.row(named: name) else { return }
        // The plugin must be visible to be selected: drop filters that would hide it.
        if !filter.matches(row.stat) { filter.clear() }
        selectedID = row.id
        pendingScrollID = row.id
    }

    /// A click on a set in the inspector: the Sets tab, that set selected (upstream OnSetRequested).
    func openSet(path: String) {
        app.searchText = ""
        app.sets.select(path: path)
        app.tab = .sets
    }

    func reveal(_ row: PluginRow) {
        guard !row.path.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: row.path) else {
            app.toast(CommonStrings.pathMissing.f(row.path), kind: .error)
            return
        }
        app.revealInFinder(path: row.path)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
