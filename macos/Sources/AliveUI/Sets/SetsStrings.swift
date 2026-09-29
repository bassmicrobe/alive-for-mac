// Mac-only: string table for the Sets feature (placeholder — the feature's
// implementer extends it). Every case needs en + ja.
import Foundation

enum SetsStrings: LocalizedStrings {
    case title, filtersTitle, tagsTitle, scanProjectsTitle, scanSamplesTitle
    case colName, colModified, colBPM, colPlugins, colFiles, colProjectSize
    case rootsEmpty, rootsAdd, rootsHint, rootOffHelp, rootRemoveHelp, moreVersions

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Sets", "セット")
        case .filtersTitle: return ("Filters", "フィルター")
        case .tagsTitle: return ("Tags and Notes", "タグとメモ")
        case .scanProjectsTitle: return ("Project Folders", "プロジェクトフォルダ")
        case .scanSamplesTitle: return ("Sample Folders", "サンプルフォルダ")
        case .colName: return ("Name", "名前")
        case .colModified: return ("Modified", "更新日")
        case .colBPM: return ("BPM", "BPM")
        case .colPlugins: return ("Plugins", "プラグイン")
        case .colFiles: return ("Files", "ファイル")
        case .colProjectSize: return ("Project size", "プロジェクトサイズ")
        case .rootsEmpty: return ("No folders yet.", "フォルダはまだありません。")
        case .rootsAdd: return ("Add Folder…", "フォルダを追加…")
        case .rootsHint: return ("Sets are read from these folders, including everything inside them.",
                                 "これらのフォルダとその中のすべてからセットを読み込みます。")
        case .rootOffHelp: return ("Include this folder when scanning", "スキャンにこのフォルダを含める")
        case .rootRemoveHelp: return ("Remove this folder from the list", "このフォルダをリストから削除")
        case .moreVersions: return ("+%lld", "+%lld")
        }
    }
}
