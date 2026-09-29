// Mac-only: the settings the shell owns. Persistence lives in `PreferenceStore` (one small place)
// until wave 1.5 moves it into the core `settings.cfg`.
import Foundation
import Observation

/// Where the plugin list comes from (upstream: Live's plugin database vs. scanning plugin folders).
enum PluginSource: String, CaseIterable, Identifiable {
    case liveDatabase
    case pluginFolders

    var id: String { rawValue }
}

@Observable
final class AppPreferences {
    /// UI language. Forwards to `Localizer.shared`, which owns persistence of this value.
    var language: LanguagePreference {
        get { Localizer.shared.preference }
        set { Localizer.shared.preference = newValue }
    }

    var transparency: Bool {
        didSet { PreferenceStore.transparency = transparency }
    }

    var dailyUpdateCheck: Bool {
        didSet { PreferenceStore.dailyUpdateCheck = dailyUpdateCheck }
    }

    var pluginSource: PluginSource {
        didSet { PreferenceStore.pluginSource = pluginSource }
    }

    init() {
        transparency = PreferenceStore.transparency
        dailyUpdateCheck = PreferenceStore.dailyUpdateCheck
        pluginSource = PreferenceStore.pluginSource
    }
}
