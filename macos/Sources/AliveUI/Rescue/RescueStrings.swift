// Mac-only: string table for the Rescue feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum RescueStrings: LocalizedStrings {
    case title

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Rescue", "レスキュー")
        }
    }
}
