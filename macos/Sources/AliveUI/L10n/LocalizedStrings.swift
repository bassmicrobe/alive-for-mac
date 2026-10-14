// Mac-only: string-table protocol. One `enum XxxStrings: LocalizedStrings` per feature, with
// exhaustive `switch` for `en` and `ja` so the compiler guarantees both translations exist.
import Foundation

protocol LocalizedStrings: CaseIterable {
    var en: String { get }
    var ja: String { get }
}

extension LocalizedStrings {
    /// The string in the current UI language.
    var s: String {
        Localizer.shared.lang == .ja ? ja : en
    }

    /// The string as a format, filled with `args` using the current language's locale.
    func f(_ args: CVarArg...) -> String {
        String(format: s, locale: Localizer.shared.locale, arguments: args)
    }
}

extension LocalizedStrings {
    /// Formats in an explicit language; for work that runs off the main actor, where
    /// `Localizer.shared` must not be read.
    func f(lang: Lang, locale: Locale, _ args: CVarArg...) -> String {
        String(format: lang == .ja ? ja : en, locale: locale, arguments: args)
    }
}
