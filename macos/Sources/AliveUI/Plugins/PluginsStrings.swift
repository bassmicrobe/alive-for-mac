// Mac-only: string table for the Plugins feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum PluginsStrings: LocalizedStrings {
    case title, filtersTitle

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Plugins", "プラグイン")
        case .filtersTitle: return ("Plugin Filters", "プラグインのフィルター")
        }
    }
}
