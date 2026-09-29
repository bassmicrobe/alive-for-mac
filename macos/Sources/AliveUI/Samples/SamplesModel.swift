// Mac-only: Samples tab: index, audition (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class SamplesModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var shownCount: Int { 0 }

    func togglePlaySelected() {}

    func rescan() {}
}
