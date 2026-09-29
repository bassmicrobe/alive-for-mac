// Mac-only: string table for the Plugins feature (upstream: the literals in MainForm.cs,
// PluginSummary.cs, PluginFiltersDialog.cs and DetailPanel.cs). Every case needs en + ja.
import Foundation

enum PluginsStrings: LocalizedStrings {
    case title
    // Columns
    case colPlugin, colDeveloper, colType, colFormat, colSets, colLastUsed, colStatus, colVersion, colFile
    // Summary cards
    case cardUsed, cardInstalled, cardMissing, cardUnused
    // States
    case statusInstalled, statusNotInstalled, statusOtherFormat, statusUnknown
    case roleInstrument, roleEffect
    // Inspector
    case detailStatus, detailFormat, detailVersion, detailCategory, detailKind, detailUsedIn, detailLastUsed
    case detailFile, detailSetsHeader, setsOne, setsMany, selectPrompt, noSetsUse, neverUsed
    case copyName, copyPath, sortBy, filtersActive
    // Aggregated notes
    case missingSummaryOne, missingSummaryMany, showThem, hideThem
    case unavailableTitle, unavailableBody, pluginSettings
    // Empty states
    case noMatchTitle, noMatchBody, noPluginsTitle, noPluginsBody
    // Filters sheet
    case filtersTitle, filterStatus, filterFormat, filterType, filterDeveloper, filterSetsCount
    case filterFrom, filterTo, filterAnyType, filterAnyDeveloper, filterOther, filterUnknown
    case filterMatches, filterReset, filterAdd, filterSearch, filterNothing

    var en: String { text.en }
    var ja: String { text.ja }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Plugins", "プラグイン")

        case .colPlugin: return ("Plugin", "プラグイン")
        case .colDeveloper: return ("Developer", "メーカー")
        case .colType: return ("Type", "タイプ")
        case .colFormat: return ("Format", "フォーマット")
        case .colSets: return ("Sets", "セット")
        case .colLastUsed: return ("Last used", "最終使用")
        case .colStatus: return ("Status", "ステータス")
        case .colVersion: return ("Version", "バージョン")
        case .colFile: return ("File", "ファイル")

        case .cardUsed: return ("Used in sets", "セットで使用")
        case .cardInstalled: return ("Installed", "インストール済み")
        case .cardMissing: return ("Not installed", "未インストール")
        case .cardUnused: return ("Never used", "未使用")

        case .statusInstalled: return ("Installed", "インストール済み")
        case .statusNotInstalled: return ("Not installed", "未インストール")
        case .statusOtherFormat: return ("Other format", "別のフォーマット")
        case .statusUnknown: return ("Unknown", "不明")
        case .roleInstrument: return ("Instrument", "インストゥルメント")
        case .roleEffect: return ("Effect", "エフェクト")

        case .detailStatus: return ("Status", "ステータス")
        case .detailFormat: return ("Format", "フォーマット")
        case .detailVersion: return ("Version", "バージョン")
        case .detailCategory: return ("Category", "カテゴリ")
        case .detailKind: return ("Kind", "種類")
        case .detailUsedIn: return ("Used in", "使用セット数")
        case .detailLastUsed: return ("Last used", "最終使用")
        case .detailFile: return ("File", "ファイル")
        case .detailSetsHeader: return ("Sets (%lld)", "セット（%lld）")
        case .setsOne: return ("%lld set", "%lld セット")
        case .setsMany: return ("%lld sets", "%lld セット")
        case .selectPrompt: return ("Select a plugin to see the sets that use it",
                                    "プラグインを選ぶと、それを使うセットが表示されます")
        case .noSetsUse: return ("No set uses this plugin", "このプラグインを使うセットはありません")
        case .neverUsed: return ("Never", "なし")
        case .copyName: return ("Copy name", "名前をコピー")
        case .copyPath: return ("Copy path", "パスをコピー")
        case .sortBy: return ("Sort by %@", "%@で並べ替え")
        case .filtersActive: return ("%lld filters", "フィルター %lld 件")

        case .missingSummaryOne: return ("1 plugin used in your sets isn't installed",
                                         "セットで使われている 1 個のプラグインが未インストールです")
        case .missingSummaryMany: return ("%lld plugins used in your sets aren't installed",
                                          "セットで使われている %lld 個のプラグインが未インストールです")
        case .showThem: return ("Show", "表示")
        case .hideThem: return ("Show all", "すべて表示")
        case .unavailableTitle: return ("Can't read the installed plugins", "インストール済みプラグインを読み取れません")
        case .unavailableBody: return ("Alive found no plugins in the Audio Unit, VST or VST3 folders, so it can't tell which ones your sets are missing. Nothing is flagged as missing.",
                                       "Audio Unit、VST、VST3 のフォルダにプラグインが見つからなかったため、セットに足りないプラグインは判別できません。未インストールとしては扱いません。")
        case .pluginSettings: return ("Plugin settings…", "プラグインの設定…")

        case .noMatchTitle: return ("No plugins match", "該当するプラグインがありません")
        case .noMatchBody: return ("Try another search or clear the filters.", "検索語を変えるか、フィルターを解除してください。")
        case .noPluginsTitle: return ("No plugins yet", "プラグインはまだありません")
        case .noPluginsBody: return ("Plugins used in your sets and plugins installed on this Mac appear here.",
                                     "セットで使われているプラグインと、この Mac にインストールされているプラグインがここに表示されます。")

        case .filtersTitle: return ("Plugin Filters", "プラグインのフィルター")
        case .filterStatus: return ("Status", "ステータス")
        case .filterFormat: return ("Format", "フォーマット")
        case .filterType: return ("Type", "タイプ")
        case .filterDeveloper: return ("Developer", "メーカー")
        case .filterSetsCount: return ("Sets count", "セット数")
        case .filterFrom: return ("from", "以上")
        case .filterTo: return ("to", "以下")
        case .filterAnyType: return ("any type", "すべてのタイプ")
        case .filterAnyDeveloper: return ("any developer", "すべてのメーカー")
        case .filterOther: return ("Other", "その他")
        case .filterUnknown: return ("Unknown", "不明")
        case .filterMatches: return ("%lld plugins match", "%lld 件が一致")
        case .filterReset: return ("Reset", "リセット")
        case .filterAdd: return ("Add", "追加")
        case .filterSearch: return ("Search", "検索")
        case .filterNothing: return ("Nothing found", "見つかりません")
        }
    }
}
