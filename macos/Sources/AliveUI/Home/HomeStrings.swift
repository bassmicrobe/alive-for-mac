// Mac-only: string table for the Home feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum HomeStrings: LocalizedStrings {
    case title, previewTitle

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Home", "ホーム")
        case .previewTitle: return ("Arrangement Preview", "アレンジメントのプレビュー")
        }
    }
}
