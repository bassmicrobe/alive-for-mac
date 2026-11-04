// Mac-only: string table for the Sets feature (list, inspector, filters, tags, folders). en + ja.
import Foundation

enum SetsStrings: LocalizedStrings {
    // Column titles
    case colName, colPlace, colModified, colCreated, colLive, colBPM, colKey, colTracks
    case colPluginCount, colFileCount, colPluginsMissed, colFilesMissed, colTags, colProjectSize
    // List
    case moreVersions, moreVersionsHelp, moreVersionsHelpOne, copyPath, pin, unpin, pinHelp, unpinHelp, playRender, playRenderHelp
    case pinnedFirst, pinnedFirstHelp, resetColumns, resetColumnsHelp, clearFilters, unreadable
    case noMatchesTitle, noMatchesBody, shownSummary, shownSummaryOneProject, shownSummaryOne
    // Inspector
    case detailEmptyTitle, detailEmptyBody, moreActions, projectSizeHelp, addTagsOrNote, noteHeading
    case versionsHeading, filesHeading, missingCount, notInstalledCount, sampleFoldersHeading
    case pluginsHeading, copyPluginList, copyPluginListHelp, pluginListCopied, onlyLiveDevices, otherFormat, showPluginHelp, pluginStatusUnknown
    case pluginListInstalled, pluginListMissing
    case rendersHeading, moreItems
    // Readiness (Mac-only)
    case readyNow, readyNowHelp, statusHeading, statusReady, statusOffline, statusMissingFiles
    case statusMissingPlugins, statusUnknown, statusUnreadable, statusUnreadableHelp, statusOfflineLine, statusStaleLine, staleRender, staleRenderHelp
    case fltReadiness, fltStaleRender, fltReadinessNone
    // Filters
    case filtersTitle, fltModified, fltFrom, fltTo, fltDateHint, fltVersion, fltKeyRoot, fltScale, fltTags, fltTracks
    case fltPluginCount, fltPlugins, fltFiles, fltRenders, fltMin, fltMax, fltNone, fltNoTags
    case fltAnyKey, fltNoKey, fltSomeMissing, fltAllInstalled, fltComplete, fltMissingFiles
    case fltHasRenders, fltNoRenders, fltMatchesProjects, fltMatchesProject1, fltMatchesSets, fltMatchesSet1, fltReset, pickDate, fltShowAll, fltShowFewer
    case calendarPrevious, calendarNext, calendarToday
    // Tags and notes
    case tagsTitle, tagsLabel, noteLabel, notePlaceholder, tagCue, removeTag, addTag, save, appliesToProject, setGone
    // Folders
    case rootsTitle, rootsProjectsTab, rootsSamplesTab, rootsHint, rootsSamplesHint
    case rootsEmpty, rootsSamplesEmpty, rootsDropHint, rootsDropRelease, rootsFromLive, rootsProjectsMark
    case rootsScan, rootsNotFolders, rootsNotFoldersOne, rootOffHelp, rootRemoveHelp, rootSetCount, rootSetCountOne
    case rootSampleCount, rootSampleCountOne
    case rootNoAccess, rootNested

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .colName: return ("Name", "名前")
        case .colPlace: return ("Place", "場所")
        case .colModified: return ("Modified", "更新日")
        case .colCreated: return ("Created", "作成日")
        case .colLive: return ("Live", "Live")
        case .colBPM: return ("BPM", "BPM")
        case .colKey: return ("Key", "キー")
        case .colTracks: return ("Tracks", "トラック")
        case .colPluginCount: return ("Plugins", "プラグイン")
        case .colFileCount: return ("Files", "ファイル")
        case .colPluginsMissed: return ("Plugins missed", "見つからないプラグイン")
        case .colFilesMissed: return ("Files missed", "見つからないファイル")
        case .colTags: return ("Tags", "タグ")
        case .colProjectSize: return ("Project size", "サイズ")

        case .moreVersions: return ("+%lld", "+%lld")
        case .moreVersionsHelp: return ("%lld more versions of this project", "このプロジェクトの他のバージョン %lld 件")
        case .moreVersionsHelpOne: return ("1 more version of this project", "このプロジェクトの他のバージョン 1 件")
        case .copyPath: return ("Copy path", "パスをコピー")
        case .pin: return ("Pin", "ピン留め")
        case .unpin: return ("Unpin", "ピン留めを解除")
        case .pinHelp: return ("Pin this set", "このセットをピン留め")
        case .unpinHelp: return ("Unpin this set", "このセットのピン留めを解除")
        case .playRender: return ("Play Render", "レンダーを再生")
        case .playRenderHelp: return ("Play the render", "レンダーを再生")
        case .pinnedFirst: return ("Pinned first", "ピン留めを先頭に")
        case .pinnedFirstHelp: return ("Keep pinned sets at the top, whatever the sort", "並べ替えに関係なくピン留めしたセットを先頭に表示")
        case .resetColumns: return ("Reset columns", "列をリセット")
        case .resetColumnsHelp: return ("Show the default columns and the default sort. Right-click a column header to show or hide columns.",
                                        "既定の列と並べ替えに戻します。列の表示/非表示は列見出しを右クリック。")
        case .clearFilters: return ("Clear filters", "フィルターを解除")
        case .unreadable: return ("unreadable", "読み込めません")
        case .noMatchesTitle: return ("No sets match", "一致するセットがありません")
        case .shownSummary: return ("%1$lld projects · %2$lld sets", "%1$lld プロジェクト・%2$lld セット")
        case .shownSummaryOneProject: return ("1 project · %lld sets", "1 プロジェクト・%lld セット")
        case .shownSummaryOne: return ("1 project · 1 set", "1 プロジェクト・1 セット")
        case .noMatchesBody: return ("Nothing passes the search and the filters.", "検索とフィルターに一致するセットはありません。")

        case .detailEmptyTitle: return ("No set selected", "セットが選択されていません")
        case .detailEmptyBody: return ("Pick one from the list to see its details.", "リストから選ぶと詳細が表示されます。")
        case .moreActions: return ("More actions", "その他の操作")
        case .projectSizeHelp: return ("Size of the whole project folder", "プロジェクトフォルダ全体のサイズ")
        case .addTagsOrNote: return ("Add tags or a note…", "タグやメモを追加…")
        case .noteHeading: return ("Note:", "メモ:")
        case .versionsHeading: return ("Versions (%lld):", "バージョン (%lld):")
        case .filesHeading: return ("Files:", "ファイル:")
        case .missingCount: return ("%lld missing", "%lld 個が見つかりません")
        case .notInstalledCount: return ("%lld not installed", "%lld 個が未インストール")
        case .sampleFoldersHeading: return ("Sample folders (%lld):", "サンプルフォルダ (%lld):")
        case .pluginsHeading: return ("Plugins (%lld):", "プラグイン (%lld):")
        case .copyPluginList: return ("copy list", "リストをコピー")
        case .copyPluginListHelp: return ("Copy this set's plugins as text: name, version, format and developer, installed ones first",
                                          "このセットのプラグインを、名前・バージョン・フォーマット・メーカーのテキストでコピー（インストール済みが先）")
        case .pluginListCopied: return ("Plugin list copied", "プラグインのリストをコピーしました")
        case .pluginListInstalled: return ("Installed:", "インストール済み:")
        case .pluginListMissing: return ("Missing:", "未インストール:")
        case .onlyLiveDevices: return ("only Live's own devices", "Live 標準のデバイスのみ")
        case .otherFormat: return ("other format", "別の形式")
        case .showPluginHelp: return ("Show %@ in the Plugins tab", "%@ をプラグインタブで表示")
        case .pluginStatusUnknown: return ("Installed plugins could not be read, so their status is unknown.",
                                           "インストール済みプラグインを読み取れないため、状態は不明です。")
        case .rendersHeading: return ("Renders (%lld):", "レンダー (%lld):")
        case .moreItems: return ("… %lld more", "… ほか %lld 件")

        case .readyNow: return ("Ready to open", "今すぐ開ける")
        case .readyNowHelp: return ("Only sets that open as saved right now: every file found, every plugin installed, no drive missing",
                                    "保存したとおりに今すぐ開けるセットだけを表示（ファイルがすべてあり、プラグインがすべてインストール済みで、未接続のドライブがない）")
        case .statusHeading: return ("Status:", "状態:")
        case .statusReady: return ("Ready to open", "開ける")
        case .statusOffline: return ("Drive not connected", "外付けドライブ未接続")
        case .statusMissingFiles: return ("Files missing", "ファイル不足")
        case .statusMissingPlugins: return ("Plugins missing", "プラグイン不足")
        case .statusUnknown: return ("Plugin status unknown", "プラグイン状況不明")
        case .statusUnreadable: return ("Can't be read", "読み込めません")
        case .statusUnreadableHelp: return ("The set file could not be read, so what it needs is unknown",
                                            "セットファイルを読み込めなかったため、必要なものが分かりません")
        case .statusOfflineLine: return ("%1$@ isn't connected (%2$lld files)", "%1$@ が未接続（%2$lld ファイル）")
        case .statusStaleLine: return ("The render is older than the set (exported %@)", "レンダーがセットより古い（%@ 書き出し）")
        case .staleRender: return ("Stale render", "レンダーが古い")
        case .staleRenderHelp: return ("The set was saved after its newest render", "最新のレンダーよりあとにセットが保存されています")
        case .fltReadiness: return ("Readiness", "開けるか")
        case .fltStaleRender: return ("stale render", "レンダーが古い")
        case .fltReadinessNone: return ("nothing to pick", "選択肢がありません")

        case .filtersTitle: return ("Filters", "フィルター")
        case .fltModified: return ("Modified", "更新日")
        case .fltFrom: return ("From", "開始")
        case .fltTo: return ("To", "終了")
        case .fltDateHint: return ("Year, month or day: YYYY / YYYY-MM / YYYY-MM-DD",
                                   "年・年月・年月日のいずれかで入力: YYYY / YYYY-MM / YYYY-MM-DD")
        case .fltVersion: return ("Live version", "Live バージョン")
        case .fltKeyRoot: return ("Key root", "キーのルート")
        case .fltScale: return ("Scale", "スケール")
        case .fltTags: return ("Tags", "タグ")
        case .fltTracks: return ("Tracks", "トラック")
        case .fltPluginCount: return ("Plugin count", "プラグイン数")
        case .fltPlugins: return ("Plugins", "プラグイン")
        case .fltFiles: return ("Files", "ファイル")
        case .fltRenders: return ("Renders", "レンダー")
        case .fltMin: return ("min", "最小")
        case .fltMax: return ("max", "最大")
        case .fltNone: return ("nothing to pick", "選択肢がありません")
        case .fltNoTags: return ("no tags yet", "タグはまだありません")
        case .fltAnyKey: return ("(any key)", "(キーあり)")
        case .fltNoKey: return ("(no key)", "(キーなし)")
        case .fltSomeMissing: return ("some not installed", "未インストールあり")
        case .fltAllInstalled: return ("all installed", "すべてインストール済み")
        case .fltComplete: return ("complete", "すべてあり")
        case .fltMissingFiles: return ("missing files", "見つからないファイル")
        case .fltHasRenders: return ("has renders", "レンダーあり")
        case .fltNoRenders: return ("no renders", "レンダーなし")
        case .fltMatchesProjects: return ("%lld projects match", "%lld 件のプロジェクトが一致")
        case .fltMatchesProject1: return ("1 project matches", "1 件のプロジェクトが一致")
        case .fltMatchesSets: return ("%lld sets match", "%lld 件のセットが一致")
        case .fltMatchesSet1: return ("1 set matches", "1 件のセットが一致")
        case .fltReset: return ("Reset", "リセット")
        case .fltShowAll: return ("Show all %lld", "すべて表示（%lld）")
        case .fltShowFewer: return ("Show fewer", "折りたたむ")
        case .pickDate: return ("Pick a date", "日付を選択")
        case .calendarPrevious: return ("Previous month", "前の月")
        case .calendarNext: return ("Next month", "次の月")
        case .calendarToday: return ("Today: %@", "今日: %@")

        case .tagsTitle: return ("Tags and Notes", "タグとメモ")
        case .tagsLabel: return ("Tags", "タグ")
        case .noteLabel: return ("Note", "メモ")
        case .notePlaceholder: return ("Add a note…", "メモを入力…")
        case .tagCue: return ("type a tag, then comma", "タグを入力してカンマ")
        case .removeTag: return ("Remove tag %@", "タグ %@ を削除")
        case .addTag: return ("Add tag %@", "タグ %@ を追加")
        case .save: return ("Save", "保存")
        case .appliesToProject: return ("Applies to the whole project folder “%@”", "プロジェクトフォルダ「%@」全体に適用されます")
        case .setGone: return ("This set is no longer in the catalog.", "このセットはカタログにありません。")

        case .rootsTitle: return ("Where to look", "探す場所")
        case .rootsProjectsTab: return ("Projects", "プロジェクト")
        case .rootsSamplesTab: return ("Samples", "サンプル")
        case .rootsHint: return ("Sets are read from these folders, including everything inside them.",
                                 "これらのフォルダとその中のすべてからセットを読み込みます。")
        case .rootsSamplesHint: return ("Samples are read from these folders and from Live's libraries you tick.",
                                        "これらのフォルダと、チェックした Live のライブラリからサンプルを読み込みます。")
        case .rootsEmpty: return ("No folders yet.", "フォルダはまだありません。")
        case .rootsSamplesEmpty: return ("No sample folders. The Samples tab will be empty.", "サンプルフォルダがありません。サンプルタブは空になります。")
        case .rootsDropHint: return ("Drag and drop folders here or click to browse…", "フォルダをここにドロップ、またはクリックして選択…")
        case .rootsDropRelease: return ("Release to add folders", "離すとフォルダを追加します")
        case .rootsFromLive: return ("From Live", "Live から")
        case .rootsProjectsMark: return ("%@ (projects)", "%@（プロジェクト）")
        case .rootsScan: return ("Scan", "スキャン")
        case .rootsNotFolders: return ("%lld items were not folders", "フォルダではない項目が %lld 件ありました")
        case .rootsNotFoldersOne: return ("1 item was not a folder", "フォルダではない項目が 1 件ありました")
        case .rootOffHelp: return ("Include this folder when scanning", "スキャンにこのフォルダを含める")
        case .rootRemoveHelp: return ("Remove this folder from the list", "このフォルダをリストから削除")
        case .rootSetCount: return ("%lld sets", "%lld セット")
        case .rootSetCountOne: return ("1 set", "1 セット")
        case .rootSampleCount: return ("%lld samples", "%lld サンプル")
        case .rootSampleCountOne: return ("1 sample", "1 サンプル")
        case .rootNoAccess: return ("no access", "アクセスできません")
        case .rootNested: return ("inside another folder", "他のフォルダ内")
        }
    }
}
