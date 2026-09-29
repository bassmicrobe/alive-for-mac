// Mac-only: Sets tab state (upstream: the sets half of MainForm). Rows = catalog → search →
// filters → fold → sort → pinned first (`SetsPipeline`), the filter itself, the column layout,
// which versions are unfolded and the tags/notes store.
import Foundation
import Observation
import SwiftUI
import AliveCore

@MainActor
@Observable
final class SetsModel {
    @ObservationIgnored unowned let app: AppModel

    /// Tags and notes (notes.cfg in the data folder), shared by the list, the inspector and the
    /// tags sheet. Changes bump `metaRevision`.
    @ObservationIgnored let meta: ProjectMeta
    private(set) var metaRevision = 0

    /// Rescans when the disk changes under an enabled root; started from `CatalogModel.start()`.
    @ObservationIgnored lazy var watcher = CatalogWatcher(app: app)

    /// The filter window edits this directly, so the list follows live like upstream.
    var filter = SetFilter()

    /// The header the user clicked (empty: newest first).
    var sortOrder: [SetSortComparator] = [] {
        didSet { if sortOrder.map(\.sort) != oldValue.map(\.sort) { scheduleSave() } }
    }

    /// Visibility, order and widths of the columns (`TableColumnCustomization`).
    var columnCustomization = TableColumnCustomization<SetEntry>() {
        didSet { scheduleSave() }
    }

    /// Folders (lowercased) whose folded versions are shown under their row. Memory only:
    /// unfolding is "let me see what is in there", not a setting.
    var expandedDirs: Set<String> = []

    /// Set to scroll the list to a path (the table's NSTableView bridge watches it).
    private(set) var scrollRequest = ScrollRequest(path: nil, serial: 0)

    struct ScrollRequest: Equatable {
        var path: String?
        var serial: Int
    }

    @ObservationIgnored private var memo: (key: MemoKey, value: SetsPipeline)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct MemoKey: Equatable {
        var revision: Int
        var query: String
        var filter: SetFilter
        var group: Bool
        var sort: SetSort?
        var pinnedFirst: Bool
        var pins: Set<String>
        var metaRevision: Int
        var pluginsKnown: Bool
    }

    init(app: AppModel) {
        self.app = app
        let meta = ProjectMeta(dir: app.dataDir)
        self.meta = meta
        meta.onChanged = { [weak self] in
            Task { @MainActor in self?.metaRevision += 1 }
        }
        let layout = SetsColumnStore.load(dir: app.dataDir)
        columnCustomization = layout.columns
        sortOrder = layout.sort.map { [SetSortComparator($0.column, order: $0.descending ? .reverse : .forward)] } ?? []
    }

    // MARK: - Rows

    var sort: SetSort? { sortOrder.first?.sort }

    /// The pipeline output for what is on screen right now (memoized on everything it depends on).
    var pipeline: SetsPipeline {
        let key = MemoKey(revision: app.catalog.revision, query: app.searchText, filter: filter,
                          group: app.settings.groupByFolder, sort: sort,
                          pinnedFirst: app.settings.pinnedFirst, pins: app.home.pinned,
                          metaRevision: metaRevision, pluginsKnown: pluginsKnown)
        if let memo, memo.key == key { return memo.value }
        let meta = meta
        let value = SetsPipeline.make(.init(
            sets: app.catalog.sets, query: key.query, filter: key.filter, groupByFolder: key.group,
            sort: key.sort, pinnedFirst: key.pinnedFirst, pins: key.pins,
            tagsOf: { meta.tagsOf($0) }, pluginsKnown: key.pluginsKnown))
        memo = (key, value)
        return value
    }

    /// The rows the list shows: one per project when grouping (unfolded versions not included).
    var rows: [SetEntry] { pipeline.heads }

    /// The toolbar's "N shown".
    var shownCount: Int { rows.count }

    /// How many condition groups of the filter are on — the number for the Filters button.
    var activeFilterCount: Int { SetsPipeline.effectiveFilter(filter, pluginsKnown: pluginsKnown).activeCount }

    /// Whether "missing plugin" is a known fact: false while the installed-plugin list could not be
    /// read. Then no missing marks are shown anywhere: the status is unknown, not missing.
    var pluginsKnown: Bool { PluginKnowledge.isKnown(app.catalog.index.inventory) }

    func set(at path: String) -> SetEntry? {
        app.catalog.sets.first { $0.path == path }
    }

    // MARK: - Selection

    /// Selects a set, unfolding its project when it is hidden under another row, and scrolls to it.
    func select(path: String?) {
        guard let path else {
            app.selectedSetPath = nil
            return
        }
        if let entry = set(at: path) {
            let key = SetsPipeline.key(forDirectory: entry.directory)
            if let head = pipeline.head(containing: path), head.path != path { expandedDirs.insert(key) }
        }
        app.selectedSetPath = path
        scrollRequest = ScrollRequest(path: path, serial: scrollRequest.serial + 1)
    }

    func isExpanded(_ directory: String) -> Bool {
        expandedDirs.contains(SetsPipeline.key(forDirectory: directory))
    }

    func setExpanded(_ directory: String, _ on: Bool) {
        let key = SetsPipeline.key(forDirectory: directory)
        if on { expandedDirs.insert(key) } else { expandedDirs.remove(key) }
    }

    // MARK: - Actions

    func setPinnedFirst(_ on: Bool) {
        app.mutateSettings { $0.pinnedFirst = on }
    }

    func playRender(of path: String) {
        app.player.playRender(forSetAt: path)
    }

    func resetColumns() {
        columnCustomization = TableColumnCustomization<SetEntry>()
        sortOrder = []
    }

    // MARK: - Tags and notes

    func tags(of set: SetEntry) -> [String] { meta.tagsOf(set.projectDir) }
    func note(of set: SetEntry) -> String { meta.noteOf(set.projectDir) }

    // MARK: - Column layout persistence

    func scheduleSave() {
        saveTask?.cancel()
        let layout = SetsColumnLayout(columns: columnCustomization, sort: sort)
        let dir = app.dataDir
        // Widths change continuously while a header edge is dragged: write once it settles.
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            SetsColumnStore.save(layout, dir: dir)
        }
    }
}
