// Mac-only: Collect All and Save (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class ExportModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }
}
