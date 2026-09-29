// Mac-only: Sets tab state. Minimal version from wave 1.5 (search + selection); the Sets
// implementer extends it with filters, sort persistence, pins and the inspector.
import Foundation
import Observation
import AliveCore

@MainActor
@Observable
final class SetsModel {
    @ObservationIgnored unowned let app: AppModel

    /// Memo of the last `rows` computation: (catalog revision, query, grouping) → rows.
    @ObservationIgnored private var memo: (key: String, rows: [SetEntry])?

    init(app: AppModel) {
        self.app = app
    }

    /// The rows the list shows: the catalog narrowed by the search box, folded by folder when
    /// `settings.groupByFolder`. Unsorted (the list sorts).
    var rows: [SetEntry] {
        let query = app.searchText
        let group = app.settings.groupByFolder
        let key = "\(app.catalog.revision)|\(group)|\(query)"
        if let memo, memo.key == key { return memo.rows }
        let rows = SetSearch.words(in: query).isEmpty
            ? app.catalog.projects
            : SetSearch.rows(app.catalog.sets, query: query, groupByFolder: group)
        memo = (key, rows)
        return rows
    }

    /// The toolbar's "N shown".
    var shownCount: Int { rows.count }

    func select(path: String?) {
        app.selectedSetPath = path
    }
}
