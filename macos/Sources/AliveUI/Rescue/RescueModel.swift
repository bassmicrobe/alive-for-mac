// Mac-only: set rescue (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class RescueModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }
}
