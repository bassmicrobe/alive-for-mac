// Mac-only: render playback for the player window (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class PlayerModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func playRender(forSetAt path: String) {}

    func togglePlayPause() {}
}
