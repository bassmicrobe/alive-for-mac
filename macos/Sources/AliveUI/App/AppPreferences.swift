// Mac-only: the settings the shell owns, as a typed view onto the core `Settings` that `AppModel`
// owns and saves to settings.cfg. There is no second store: every setter writes through
// `AppModel.mutateSettings`.
import Foundation
import Observation

/// Where the plugin list comes from (upstream: Live's plugin database vs. scanning plugin folders).
/// Stored as `Settings.pluginsFromFolders` (key `pluginfolders`).
enum PluginSource: String, CaseIterable, Identifiable {
    case liveDatabase
    case pluginFolders

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppPreferences {
    @ObservationIgnored private unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// UI language (`settings.lang`). Also drives `Localizer.shared`, which re-renders every view.
    var language: LanguagePreference {
        get { LanguagePreference(configValue: app.settings.lang) }
        set {
            Localizer.shared.preference = newValue
            app.mutateSettings { $0.lang = newValue.configValue }
        }
    }

    /// Translucent window (`!settings.disableGlass`, key `noglass`).
    var transparency: Bool {
        get { !app.settings.disableGlass }
        set { app.mutateSettings { $0.disableGlass = !newValue } }
    }

    /// Daily update check (`settings.checkUpdates`).
    var dailyUpdateCheck: Bool {
        get { app.settings.checkUpdates }
        set { app.mutateSettings { $0.checkUpdates = newValue } }
    }

    /// Plugin list source (`settings.pluginsFromFolders`). Changing it rescans: the plugin inventory
    /// is rebuilt by the scan.
    var pluginSource: PluginSource {
        get { app.settings.pluginsFromFolders ? .pluginFolders : .liveDatabase }
        set {
            guard newValue != pluginSource else { return }
            app.mutateSettings { $0.pluginsFromFolders = (newValue == .pluginFolders) }
            app.catalog.rescan()
        }
    }
}
