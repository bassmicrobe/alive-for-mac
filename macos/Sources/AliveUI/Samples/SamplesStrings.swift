// Mac-only: string table for the Samples feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum SamplesStrings: LocalizedStrings {
    case title

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Samples", "サンプル")
        }
    }
}
