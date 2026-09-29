// Mac-only: Plugins tab: inventory, filters (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class PluginsModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var shownCount: Int { 0 }

    /// Opens the Plugins tab on one plugin (from a set's plugin list in the Sets inspector).
    /// Cross-feature entry point: keep this signature.
    func show(pluginNamed name: String) {
        app.tab = .plugins
    }
}
