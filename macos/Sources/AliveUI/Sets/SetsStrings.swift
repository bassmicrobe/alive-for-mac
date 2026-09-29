// Mac-only: string table for the Sets feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum SetsStrings: LocalizedStrings {
    case title, filtersTitle, tagsTitle, scanProjectsTitle, scanSamplesTitle

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Sets", "セット")
        case .filtersTitle: return ("Filters", "フィルター")
        case .tagsTitle: return ("Tags and Notes", "タグとメモ")
        case .scanProjectsTitle: return ("Project Folders", "プロジェクトフォルダ")
        case .scanSamplesTitle: return ("Sample Folders", "サンプルフォルダ")
        }
    }
}
