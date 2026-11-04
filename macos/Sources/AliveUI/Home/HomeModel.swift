// Port of the data side of src/HomeView.cs (Projects(), Pinned()) and src/HomeStore.cs use.
import AliveCore
import Foundation
import Observation

/// What the Projects grid shows, as a pure function of its inputs.
enum HomeListing {
    struct Result: Equatable {
        /// One tile per set (per folder when grouped), in screen order.
        var rows: [SetEntry]
        /// The pinned projects that match the search, in pin order: what the star above the grid acts on.
        var pinned: [SetEntry]
    }

    /// One tile per set (per folder when `groupByFolder`), newest first; the pinned ones first in
    /// pin order when `pinnedFirst`. The search filters first and only then folds by folder, so a
    /// query for a name that only an older version carries still finds it.
    static func projects(sets: [SetEntry], query: String, groupByFolder: Bool,
                         pinOrder: [String], pinnedFirst: Bool,
                         tagsOf: (String) -> [String] = { _ in [] },
                         noteOf: (String) -> String = { _ in "" }) -> [SetEntry] {
        listing(sets: sets, query: query, groupByFolder: groupByFolder, pinOrder: pinOrder,
                pinnedFirst: pinnedFirst, tagsOf: tagsOf, noteOf: noteOf).rows
    }

    static func listing(sets: [SetEntry], query: String, groupByFolder: Bool,
                        pinOrder: [String], pinnedFirst: Bool,
                        tagsOf: (String) -> [String], noteOf: (String) -> String) -> Result {
        // The one rule of the search box, shared with the Sets table (9ce4b4b): name, folder,
        // plugins, renders, tags and note.
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = q.isEmpty ? sets : sets.filter {
            SetFilter.matchesSearch($0, query: q, tagsOf: tagsOf, noteOf: noteOf)
        }
        var all = matched.filter { !$0.isBackup }
        if groupByFolder { all = ProjectIndex.collapseByFolder(all) }

        // By the list of pins rather than by every set: the pin order is the order on screen and
        // must not jump about.
        let byPath = Dictionary(matched.map { ($0.path.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let pins = pinOrder.compactMap { byPath[$0.lowercased()] }

        // A version was pinned and then a fresh one saved next to it: the old one goes under the
        // collapsed row and the pin would silently stop working. Bring it back.
        var present = Set(all.map { $0.path.lowercased() })
        for p in pins where present.insert(p.path.lowercased()).inserted { all.append(p) }

        all.sort { a, b in a.modified != b.modified ? a.modified > b.modified : a.path < b.path }
        guard pinnedFirst, !pins.isEmpty else { return Result(rows: all, pinned: pins) }

        // To the top, in pin order: it must not jump about with the edit date.
        let pinnedKeys = Set(pins.map { $0.path.lowercased() })
        return Result(rows: pins + all.filter { !pinnedKeys.contains($0.path.lowercased()) }, pinned: pins)
    }
}

/// Arrow-key movement over a grid of `columns` tiles. Slot 0 is the "New Live Set" tile, which
/// is not selectable, so indices here are into the sets only.
enum TileNavigation {
    enum Direction { case left, right, up, down, first, last }

    /// The new index, or nil when the move leaves the grid. `nil` current starts at the first tile.
    /// Home and End go to the ends from anywhere, selection or not (a6c8dc1).
    static func move(from current: Int?, _ direction: Direction, columns: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        if direction == .first { return 0 }
        if direction == .last { return count - 1 }
        guard let current else { return 0 }
        // The first row is shifted by one slot by the "New Live Set" tile.
        let slot = current + 1
        let target: Int
        switch direction {
        case .left: target = slot - 1
        case .right: target = slot + 1
        case .up: target = slot - columns
        case .down: target = slot + columns
        case .first, .last: return nil
        }
        let index = target - 1
        if index < 0 || index >= count { return direction == .down && current < count - 1 ? count - 1 : nil }
        return index
    }
}

/// How many projects open as saved right now.
struct ReadySummary: Equatable {
    var ready = 0
    var total = 0
}

@MainActor
@Observable
final class HomeModel {
    @ObservationIgnored unowned let app: AppModel

    /// Stars (home.cfg). Shared by Home tiles, the Sets list and the ⌘D menu item.
    @ObservationIgnored private let store: HomeStore
    private(set) var pinned: Set<String>
    private var pinOrder: [String]

    /// Pictures for tiles and the Sets inspector.
    @ObservationIgnored let thumbnails: ThumbnailPipeline
    /// The big preview reads through its own loader so that tiles do not evict it.
    @ObservationIgnored let previewLoader = ArrangementLoader()

    /// Bumped by ↓ in the search field: the grid takes the keyboard focus (see `enterFromSearch`).
    private(set) var gridFocusRequest = 0

    @ObservationIgnored private var rowsCache: (key: RowsKey, listing: HomeListing.Result)?
    @ObservationIgnored private var readyCache: (key: Int, summary: ReadySummary)?
    @ObservationIgnored private var statsCache: (key: Int, stats: OverviewStats)?
    @ObservationIgnored private var heatmapCache: (key: HeatmapKey, grid: HeatmapGrid)?

    private struct RowsKey: Equatable {
        var revision: Int
        var query: String
        var grouped: Bool
        var pinnedFirst: Bool
        var pins: [String]
        /// Tags and notes are searched too.
        var metaRevision: Int
    }

    private struct HeatmapKey: Equatable {
        var revision: Int
        var today: Date
    }

    init(app: AppModel) {
        self.app = app
        let store = HomeStore(dir: app.dataDir)
        self.store = store
        pinOrder = store.pins
        pinned = Set(store.pins)
        thumbnails = ThumbnailPipeline(dataDir: app.dataDir)
    }

    // MARK: - Projects

    /// The tiles: the catalog narrowed by the search box (memoized).
    var rows: [SetEntry] { listing.rows }

    private var listing: HomeListing.Result {
        let key = RowsKey(revision: app.catalog.revision, query: app.searchText,
                          grouped: app.settings.groupByFolder, pinnedFirst: app.settings.pinnedFirst, pins: pinOrder,
                          metaRevision: app.sets.metaRevision)
        if let cache = rowsCache, cache.key == key { return cache.listing }
        let meta = app.sets.meta
        let listing = HomeListing.listing(sets: app.catalog.sets, query: key.query, groupByFolder: key.grouped,
                                          pinOrder: key.pins, pinnedFirst: key.pinnedFirst,
                                          tagsOf: { meta.tagsOf($0) }, noteOf: { meta.noteOf($0) })
        rowsCache = (key, listing)
        return listing
    }

    var shownCount: Int { rows.count }

    /// The toolbar's counter on Home: "1 project shown", "12 projects shown".
    var shownLabel: String { HomeStrings.projectsShown(shownCount) }

    /// The star above the grid is there only while there is something pinned to put first (0bb4915).
    var hasPinned: Bool { !listing.pinned.isEmpty }

    var pinnedFirst: Bool { app.settings.pinnedFirst }

    func togglePinnedFirst() {
        app.mutateSettings { $0.pinnedFirst.toggle() }
    }

    // MARK: - Pins

    func isPinned(_ path: String) -> Bool { pinned.contains(path) }

    func togglePin(path: String) {
        _ = store.togglePin(path)
        pinOrder = store.pins
        pinned = Set(pinOrder)
    }

    // MARK: - Overview

    var overviewStats: OverviewStats {
        let revision = app.catalog.revision
        if let cache = statsCache, cache.key == revision { return cache.stats }
        let stats = OverviewStats.compute(history: app.catalog.history, sets: app.catalog.sets)
        statsCache = (revision, stats)
        return stats
    }

    /// "N of M projects open right now" for the Overview.
    var readySummary: ReadySummary {
        let revision = app.catalog.revision
        if let cache = readyCache, cache.key == revision { return cache.summary }
        let heads = app.catalog.projects.filter { !$0.isBackup }
        let summary = ReadySummary(ready: heads.filter { app.sets.status(of: $0).readiness == .ready }.count,
                                   total: heads.count)
        readyCache = (revision, summary)
        return summary
    }

    /// Switches to the Sets tab showing only the sets that open right now.
    func showReadySets() {
        app.sets.filter.readiness = [.ready]
        app.tab = .sets
    }

    /// The year calendar. The date is part of the key: the window moves at every midnight.
    var heatmap: HeatmapGrid {
        let key = HeatmapKey(revision: app.catalog.revision, today: Calendar.current.startOfDay(for: Date()))
        if let cache = heatmapCache, cache.key == key { return cache.grid }
        let history = app.catalog.history
        let grid = HeatmapGrid.make(today: key.today, saves: { history.saves(on: $0) })
        heatmapCache = (key, grid)
        return grid
    }

    // MARK: - Actions

    func select(_ path: String) { app.selectedSetPath = path }

    /// A search or a re-sort took the selected tile away: it stops being the selection, or ⌘O would
    /// still open a project nobody can see (9ce4b4b). Called by the grid when its tiles change.
    func dropHiddenSelection() {
        guard app.tab == .home else { return }
        let kept = HomeSelection.kept(app.selectedSetPath, in: rows)
        if kept != app.selectedSetPath { app.selectedSetPath = kept }
    }

    /// Takes the person to a project's tile (upstream `NavigateToSet`): selected, and the grid
    /// scrolls to it. A search that hides the project is cleared first (9ce4b4b).
    func show(path: String) {
        if !hasTile(path), !app.searchText.isEmpty { app.searchText = "" }
        app.selectedSetPath = tilePath(for: path)
    }

    private func hasTile(_ path: String) -> Bool { rows.contains { $0.path == path } }

    /// The tile that stands for a set: its own, or, when it is folded under a newer version of its
    /// folder, that version's.
    private func tilePath(for path: String) -> String {
        if hasTile(path) { return path }
        guard let set = app.catalog.sets.first(where: { $0.path == path }) else { return path }
        let folder = set.directory.lowercased()
        return rows.first { $0.directory.lowercased() == folder }?.path ?? path
    }

    /// ↓ in the search field goes on into the tiles: the picked one keeps the keyboard, otherwise
    /// the first (a6c8dc1 `IntoResults`). The field calls this when the Home tab is showing.
    func enterFromSearch() {
        guard let path = HomeSelection.entry(selected: app.selectedSetPath, in: rows) else { return }
        app.selectedSetPath = path
        gridFocusRequest += 1
    }

    /// The projects saved on a day of the calendar, busiest first (a6c8dc1).
    func dayProjects(on day: Date) -> [DayProject] {
        HomeDay.projects(dirs: app.catalog.history.projects(on: day), sets: app.catalog.sets)
    }

    /// The subtitle under a tile's name: "2026-09-25   ·   bass music".
    static func subtitle(for set: SetEntry) -> String {
        let date = set.modified > .distantPast ? dateText(set.modified) : ""
        let place = set.place
        return place.isEmpty ? date : date + "   ·   " + place
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateText(_ date: Date) -> String { dayFormatter.string(from: date) }
}
