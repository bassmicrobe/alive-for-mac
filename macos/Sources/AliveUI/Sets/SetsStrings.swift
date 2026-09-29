// Mac-only: string table for the Sets feature (list, inspector, filters, tags, folders). en + ja.
import Foundation

enum SetsStrings: LocalizedStrings {
    // Column titles
    case colName, colPlace, colModified, colCreated, colLive, colBPM, colKey, colTracks
    case colPluginCount, colFileCount, colPluginsMissed, colFilesMissed, colTags, colProjectSize
    // List
    case moreVersions, moreVersionsHelp, pin, unpin, pinHelp, unpinHelp, playRender, playRenderHelp
    case pinnedFirst, pinnedFirstHelp, resetColumns, resetColumnsHelp, clearFilters, unreadable
    case noMatchesTitle, noMatchesBody
    // Inspector
    case detailEmptyTitle, detailEmptyBody, moreActions, projectSizeHelp, addTagsOrNote, noteHeading
    case versionsHeading, filesHeading, fileCount, missingCount, notInstalledCount, sampleFoldersHeading
    case pluginsHeading, onlyLiveDevices, otherFormat, showPluginHelp, pluginStatusUnknown
    case rendersHeading, moreItems
    // Filters
    case filtersTitle, fltModified, fltFrom, fltTo, fltVersion, fltKeyRoot, fltScale, fltTags, fltTracks
    case fltPluginCount, fltPlugins, fltFiles, fltRenders, fltMin, fltMax, fltNone, fltNoTags
    case fltAnyKey, fltNoKey, fltSomeMissing, fltAllInstalled, fltComplete, fltMissingFiles
    case fltHasRenders, fltNoRenders, fltMatches, fltReset, pickDate
    // Tags and notes
    case tagsTitle, tagsLabel, noteLabel, tagCue, removeTag, addTag, save, appliesToProject, setGone
    // Folders
    case rootsTitle, rootsProjectsTab, rootsSamplesTab, rootsHint, rootsSamplesHint
    case rootsEmpty, rootsSamplesEmpty, rootsDropHint, rootsDropRelease, rootsFromLive, rootsProjectsMark
    case rootsScan, rootsNotFolders, rootOffHelp, rootRemoveHelp, rootSetCount, rootSampleCount
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
        case .colProjectSize: return ("Project size", "プロジェクトサイズ")

        case .moreVersions: return ("+%lld", "+%lld")
        case .moreVersionsHelp: return ("%lld more versions of this project", "このプロジェクトの他のバージョン %lld 件")
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
        case .noMatchesBody: return ("Nothing passes the search and the filters.", "検索とフィルターに一致するセットはありません。")

        case .detailEmptyTitle: return ("No set selected", "セットが選択されていません")
        case .detailEmptyBody: return ("Pick one from the list to see its details.", "リストから選ぶと詳細が表示されます。")
        case .moreActions: return ("More actions", "その他の操作")
        case .projectSizeHelp: return ("Size of the whole project folder", "プロジェクトフォルダ全体のサイズ")
        case .addTagsOrNote: return ("Add tags or a note…", "タグやメモを追加…")
        case .noteHeading: return ("Note:", "メモ:")
        case .versionsHeading: return ("Versions (%lld):", "バージョン (%lld):")
        case .filesHeading: return ("Files:", "ファイル:")
        case .fileCount: return ("%lld files", "%lld 個のファイル")
        case .missingCount: return ("%lld missing", "%lld 個が見つかりません")
        case .notInstalledCount: return ("%lld not installed", "%lld 個が未インストール")
        case .sampleFoldersHeading: return ("Sample folders (%lld):", "サンプルフォルダ (%lld):")
        case .pluginsHeading: return ("Plugins (%lld):", "プラグイン (%lld):")
        case .onlyLiveDevices: return ("only Live's own devices", "Live 標準のデバイスのみ")
        case .otherFormat: return ("other format", "別の形式")
        case .showPluginHelp: return ("Show %@ in the Plugins tab", "%@ をプラグインタブで表示")
        case .pluginStatusUnknown: return ("Installed plugins could not be read, so their status is unknown.",
                                           "インストール済みプラグインを読み取れないため、状態は不明です。")
        case .rendersHeading: return ("Renders (%lld):", "レンダー (%lld):")
        case .moreItems: return ("… %lld more", "… ほか %lld 件")

        case .filtersTitle: return ("Filters", "フィルター")
        case .fltModified: return ("Modified", "更新日")
        case .fltFrom: return ("from  2026-01", "開始  2026-01")
        case .fltTo: return ("to  2026-08-07", "終了  2026-08-07")
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
        case .fltMatches: return ("%1$lld of %2$lld sets match", "%2$lld 件中 %1$lld 件が一致")
        case .fltReset: return ("Reset", "リセット")
        case .pickDate: return ("Pick a date", "日付を選択")

        case .tagsTitle: return ("Tags and Notes", "タグとメモ")
        case .tagsLabel: return ("Tags", "タグ")
        case .noteLabel: return ("Note", "メモ")
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
        case .rootOffHelp: return ("Include this folder when scanning", "スキャンにこのフォルダを含める")
        case .rootRemoveHelp: return ("Remove this folder from the list", "このフォルダをリストから削除")
        case .rootSetCount: return ("%lld sets", "%lld セット")
        case .rootSampleCount: return ("%lld samples", "%lld サンプル")
        case .rootNoAccess: return ("no access", "アクセスできません")
        case .rootNested: return ("inside another folder", "他のフォルダ内")
        }
    }
}
