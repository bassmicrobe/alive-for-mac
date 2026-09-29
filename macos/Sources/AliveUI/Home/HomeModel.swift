// Port of the data side of src/HomeView.cs (Projects(), Pinned()) and src/HomeStore.cs use.
import AliveCore
import Foundation
import Observation

/// What the Projects grid shows, as a pure function of its inputs.
enum HomeListing {
    /// One tile per set (per folder when `groupByFolder`), newest first; the pinned ones first in
    /// pin order when `pinnedFirst`. The search filters first and only then folds by folder, so a
    /// query for a name that only an older version carries still finds it.
    static func projects(sets: [SetEntry], query: String, groupByFolder: Bool,
                         pinOrder: [String], pinnedFirst: Bool) -> [SetEntry] {
        let matched = SetSearch.words(in: query).isEmpty ? sets : sets.filter { SetSearch.matches($0, query: query) }
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
        guard pinnedFirst, !pins.isEmpty else { return all }

        // To the top, in pin order: it must not jump about with the edit date.
        let pinnedKeys = Set(pins.map { $0.path.lowercased() })
        return pins + all.filter { !pinnedKeys.contains($0.path.lowercased()) }
    }
}

/// Arrow-key movement over a grid of `columns` tiles. Slot 0 is the "New Live Set" tile, which
/// is not selectable, so indices here are into the sets only.
enum TileNavigation {
    enum Direction { case left, right, up, down }

    /// The new index, or nil when the move leaves the grid. `nil` current starts at the first tile.
    static func move(from current: Int?, _ direction: Direction, columns: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        // The first row is shifted by one slot by the "New Live Set" tile.
        let slot = current + 1
        let target: Int
        switch direction {
        case .left: target = slot - 1
        case .right: target = slot + 1
        case .up: target = slot - columns
        case .down: target = slot + columns
        }
        let index = target - 1
        if index < 0 || index >= count { return direction == .down && current < count - 1 ? count - 1 : nil }
        return index
    }
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

    @ObservationIgnored private var rowsCache: (key: RowsKey, rows: [SetEntry])?
    @ObservationIgnored private var statsCache: (key: Int, stats: OverviewStats)?
    @ObservationIgnored private var heatmapCache: (key: HeatmapKey, grid: HeatmapGrid)?

    private struct RowsKey: Equatable {
        var revision: Int
        var query: String
        var grouped: Bool
        var pinnedFirst: Bool
        var pins: [String]
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
    var rows: [SetEntry] {
        let key = RowsKey(revision: app.catalog.revision, query: app.searchText,
                          grouped: app.settings.groupByFolder, pinnedFirst: app.settings.pinnedFirst, pins: pinOrder)
        if let cache = rowsCache, cache.key == key { return cache.rows }
        let rows = HomeListing.projects(sets: app.catalog.sets, query: key.query, groupByFolder: key.grouped,
                                        pinOrder: key.pins, pinnedFirst: key.pinnedFirst)
        rowsCache = (key, rows)
        return rows
    }

    var shownCount: Int { rows.count }

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
