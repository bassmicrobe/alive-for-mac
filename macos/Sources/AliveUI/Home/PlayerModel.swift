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

    /// The app-wide player (`app.audio`), shared with sample audition.
    var audio: AudioPlayback { app.audio }

    func playRender(forSetAt path: String) {}

    func togglePlayPause() { audio.togglePlayPause() }
}
