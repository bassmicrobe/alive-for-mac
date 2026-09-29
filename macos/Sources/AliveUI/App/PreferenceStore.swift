// Mac-only: the single place preferences are persisted. Wave 1.5 swaps this for the core
// `settings.cfg` (keys: lang, transparency, dailyUpdateCheck, pluginSource) — change only here.
import Foundation

enum PreferenceStore {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let language = "alive.lang"
        static let transparency = "alive.transparency"
        static let dailyUpdateCheck = "alive.dailyUpdateCheck"
        static let pluginSource = "alive.pluginSource"
    }

    static var language: LanguagePreference {
        get { LanguagePreference(configValue: defaults.string(forKey: Key.language)) }
        set { defaults.set(newValue.configValue, forKey: Key.language) }
    }

    static var transparency: Bool {
        get { defaults.bool(forKey: Key.transparency) }
        set { defaults.set(newValue, forKey: Key.transparency) }
    }

    static var dailyUpdateCheck: Bool {
        get { defaults.bool(forKey: Key.dailyUpdateCheck) }
        set { defaults.set(newValue, forKey: Key.dailyUpdateCheck) }
    }

    static var pluginSource: PluginSource {
        get { PluginSource(rawValue: defaults.string(forKey: Key.pluginSource) ?? "") ?? .liveDatabase }
        set { defaults.set(newValue.rawValue, forKey: Key.pluginSource) }
    }
}
