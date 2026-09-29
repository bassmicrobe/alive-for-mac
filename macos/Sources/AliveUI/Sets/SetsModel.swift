// Mac-only: Sets tab: list, sort, filter, selection (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class SetsModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var shownCount: Int { 0 }

    func select(path: String?) {
        app.selectedSetPath = path
    }
}
