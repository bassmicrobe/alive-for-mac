// Mac-only: runtime language switching (System / English / 日本語). See docs/PORTING.md §6.
import Foundation
import Observation

enum Lang: String, CaseIterable, Sendable {
    case en, ja
}

enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system, en, ja

    var id: String { rawValue }

    /// Value stored in `settings.cfg` (`lang=system|en|ja`).
    var configValue: String { rawValue }

    init(configValue: String?) {
        self = configValue.flatMap(LanguagePreference.init(rawValue:)) ?? .system
    }

    /// Each language is listed in its own language, regardless of the current UI language.
    /// `system` is the only entry that has to follow the UI language (see SettingsStrings).
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

/// Views read `Localizer.shared` while building `body`, so changing `preference` re-renders them.
@Observable
final class Localizer {
    static let shared = Localizer()

    var preference: LanguagePreference {
        didSet {
            guard preference != oldValue else { return }
            Localizer.applyAppleLanguages(preference)
        }
    }

    /// Persistence is `AppModel`'s job (`settings.lang`); it sets `preference` from there at launch.
    init(preference: LanguagePreference = .system) {
        self.preference = preference
    }

    var lang: Lang {
        switch preference {
        case .en: return .en
        case .ja: return .ja
        case .system: return Localizer.systemLang
        }
    }

    var locale: Locale {
        switch lang {
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        }
    }

    /// The OS language, read from the global domain: our own `AppleLanguages` override in the app
    /// domain must not leak into what "System" means.
    static var systemLang: Lang {
        let global = CFPreferencesCopyValue(
            "AppleLanguages" as CFString, kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        let first = (global ?? Locale.preferredLanguages).first ?? "en"
        return first.hasPrefix("ja") ? .ja : .en
    }

    /// Makes system-provided UI (open panels, standard menu items) follow after a relaunch.
    private static func applyAppleLanguages(_ preference: LanguagePreference) {
        let defaults = UserDefaults.standard
        switch preference {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .en: defaults.set(["en"], forKey: "AppleLanguages")
        case .ja: defaults.set(["ja"], forKey: "AppleLanguages")
        }
    }
}
