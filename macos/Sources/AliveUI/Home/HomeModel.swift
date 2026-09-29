// Mac-only: Home tab: pinned sets, tiles, activity (placeholder — replaced by the feature's implementer).
import AliveCore
import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    @ObservationIgnored unowned let app: AppModel

    /// Stars (home.cfg). Shared by Home tiles, the Sets list and the ⌘D menu item.
    @ObservationIgnored private let store: HomeStore
    private(set) var pinned: Set<String>

    init(app: AppModel) {
        self.app = app
        store = HomeStore(dir: app.dataDir)
        pinned = Set(store.pins)
    }

    var shownCount: Int { 0 }

    func isPinned(_ path: String) -> Bool { pinned.contains(path) }

    func togglePin(path: String) {
        _ = store.togglePin(path)
        pinned = Set(store.pins)
    }
}
