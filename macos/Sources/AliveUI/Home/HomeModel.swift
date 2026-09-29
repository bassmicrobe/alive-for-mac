// Mac-only: Home tab: pinned sets, tiles, activity (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var shownCount: Int { 0 }

    func togglePin(path: String) {}
}
