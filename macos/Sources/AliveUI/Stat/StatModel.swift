// Mac-only: Stat window numbers (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class StatModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }
}
