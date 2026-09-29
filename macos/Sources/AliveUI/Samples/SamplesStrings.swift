// Mac-only: string table for the Samples feature. Every case needs en + ja.
import Foundation

enum SamplesStrings: LocalizedStrings {
    case title
    // Lenses
    case lensAll, lensNeverUsed, lensMostUsed, lensDuplicates, lensHelp
    // Columns (the name column is called after what the view lists)
    case colName, colFolder, colSample, colLocation, colSamples, colUsed, colCopies, colProjects
    case colLastUsed, colCreated, colModified, colSize, columnsMenu
    // Cells
    case usageUnknown, never, noValue, sizeKB, sizeMB, sizeGB
    // Counter and progress
    case countSamples, countSamplesBare, countOneSample, countOneBare, countCut, countDuplicates, indexing, indexingCount
    // Empty states
    case emptyTitle, emptyBody, chooseFolders, chooseFoldersMessage, manageHint
    case suggestionLibrary, suggestionPacks, suggestionCore
    case noSamplesTitle, noSamplesBody, noMatchTitle, noMatchBody, clearSearch
    // Rows and menus
    case play, stop, expand, collapse, folderItems, waveSeek, showInTree, copyPath, playing, notPlayable, dragHelp
    // Panel
    case panelNoSelection, panelNoSelectionHint, panelSamples, panelUsed, panelProjects, panelLastUsed
    case panelCreated, panelCopies, panelDuration, panelFormat, panelByMonth, panelMostUsed
    case panelProjectsList, panelCopiesList, panelMore, panelUsedShare, panelCopiesValue
    case waveReading, waveOnlyLive, waveNone, formatMono, formatStereo, formatChannels, formatKHz, formatBits
    case usedTag
    // Outside the library
    case outsideTitle, outsideBody, addAsFolder
    // Toasts
    case alreadyInLibrary

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Samples", "サンプル")
        case .lensAll: return ("All folders", "すべてのフォルダ")
        case .lensNeverUsed: return ("Never used", "未使用")
        case .lensMostUsed: return ("Most used", "よく使う")
        case .lensDuplicates: return ("Duplicates", "重複")
        case .lensHelp: return ("Look at the library through: the folder tree, the heaviest folders nothing was taken from, your go-to sounds, or the same file in several places.",
                                "ライブラリの見方: フォルダツリー、一度も使っていない大きなフォルダ、よく使う音、複数の場所にある同じファイル。")
        case .colName: return ("Name", "名前")
        case .colFolder: return ("Folder", "フォルダ")
        case .colSample: return ("Sample", "サンプル")
        case .colLocation: return ("Location", "場所")
        case .colSamples: return ("Samples", "サンプル数")
        case .colUsed: return ("Used", "使用")
        case .colCopies: return ("Copies", "コピー")
        case .colProjects: return ("Projects", "プロジェクト")
        case .colLastUsed: return ("Last used", "最終使用")
        case .colCreated: return ("Created", "作成日")
        case .colModified: return ("Modified", "更新日")
        case .colSize: return ("Size", "サイズ")
        case .columnsMenu: return ("Columns", "列")
        case .usageUnknown: return ("…", "…")
        case .never: return ("never", "未使用")
        case .noValue: return ("none", "なし")
        case .sizeKB: return ("%@ KB", "%@ KB")
        case .sizeMB: return ("%@ MB", "%@ MB")
        case .sizeGB: return ("%@ GB", "%@ GB")
        case .countSamples: return ("%1$@ samples · %2$@", "%1$@ 個のサンプル · %2$@")
        case .countSamplesBare: return ("%@ samples", "%@ 個のサンプル")
        case .countOneBare: return ("1 sample", "1 個のサンプル")
        case .countOneSample: return ("1 sample · %@", "1 個のサンプル · %@")
        case .countCut: return ("first %1$@ of %2$@", "%2$@ 件中の先頭 %1$@ 件")
        case .countDuplicates: return ("%1$@ shown · %2$@ extra", "%1$@ 件を表示 · 余分 %2$@")
        case .indexing: return ("Indexing samples…", "サンプルのインデックスを作成中…")
        case .indexingCount: return ("Indexing samples… %@", "サンプルのインデックスを作成中… %@")
        case .emptyTitle: return ("No sample folders yet", "サンプルフォルダがまだありません")
        case .emptyBody: return ("Point Alive at your sample folders, or take the ones Live already knows. Alive only reads them; it never moves or deletes a sample.",
                                 "サンプルのフォルダを指定するか、Live が知っているフォルダを使います。Alive は読み取るだけで、サンプルの移動や削除はしません。")
        case .chooseFolders: return ("Choose folders…", "フォルダを選択…")
        case .chooseFoldersMessage: return ("Choose the folders that contain your samples", "サンプルが入っているフォルダを選択")
        case .manageHint: return ("Change these any time with Scan Folders (⇧⌘O).", "これらはいつでも「スキャンするフォルダ」(⇧⌘O)で変更できます。")
        case .suggestionLibrary: return ("User Library", "ユーザーライブラリ")
        case .suggestionPacks: return ("Packs", "パック")
        case .suggestionCore: return ("Core Library", "コアライブラリ")
        case .noSamplesTitle: return ("No samples found", "サンプルが見つかりません")
        case .noSamplesBody: return ("The sample folders hold no audio files Live can load.", "サンプルフォルダに Live で読み込める音声ファイルがありません。")
        case .noMatchTitle: return ("No samples match", "一致するサンプルがありません")
        case .noMatchBody: return ("Try another search or choose All folders.", "検索語を変えるか、「すべてのフォルダ」を選んでください。")
        case .clearSearch: return ("Clear search", "検索をクリア")
        case .folderItems: return ("%lld items", "%lld 個の項目")
        case .waveSeek: return ("Playback position", "再生位置")
        case .play: return ("Play", "再生")
        case .stop: return ("Stop", "停止")
        case .expand: return ("Expand", "展開")
        case .collapse: return ("Collapse", "折りたたむ")
        case .showInTree: return ("Show in tree", "ツリーで表示")
        case .copyPath: return ("Copy path", "パスをコピー")
        case .playing: return ("Playing", "再生中")
        case .notPlayable: return ("Only Live plays this file", "この形式は Live でのみ再生できます")
        case .dragHelp: return ("Drag into Live", "Live にドラッグ")
        case .panelNoSelection: return ("No folder selected", "フォルダが選択されていません")
        case .panelNoSelectionHint: return ("Pick a folder or a sample", "フォルダかサンプルを選んでください")
        case .panelSamples: return ("Samples:", "サンプル数:")
        case .panelUsed: return ("Used:", "使用:")
        case .panelProjects: return ("Projects:", "プロジェクト:")
        case .panelLastUsed: return ("Last used:", "最終使用:")
        case .panelCreated: return ("Created:", "作成日:")
        case .panelCopies: return ("Copies:", "コピー:")
        case .panelDuration: return ("Duration:", "長さ:")
        case .panelFormat: return ("Format:", "形式:")
        case .panelByMonth: return ("Projects by month:", "月ごとのプロジェクト数:")
        case .panelMostUsed: return ("Most used (%lld):", "よく使う (%lld):")
        case .panelProjectsList: return ("Projects (%lld):", "プロジェクト (%lld):")
        case .panelCopiesList: return ("Copies (%lld):", "コピー (%lld):")
        case .panelMore: return ("… %@ more", "… ほか %@ 件")
        case .panelUsedShare: return ("%1$@ · %2$@", "%1$@ · %2$@")
        case .panelCopiesValue: return ("%1$@ · %2$@", "%1$@ · %2$@")
        case .waveReading: return ("reading…", "読み込み中…")
        case .waveOnlyLive: return ("only Live plays this file", "この形式は Live でのみ再生できます")
        case .waveNone: return ("no picture for this file", "波形を表示できません")
        case .formatMono: return ("mono", "モノラル")
        case .formatStereo: return ("stereo", "ステレオ")
        case .formatChannels: return ("%lld channels", "%lld チャンネル")
        case .formatKHz: return ("%@ kHz", "%@ kHz")
        case .formatBits: return ("%lld-bit", "%lld ビット")
        case .usedTag: return ("used", "使用中")
        case .outsideTitle: return ("Not in the sample library", "サンプルライブラリにありません")
        case .outsideBody: return ("%@ lies outside the folders Alive indexes.", "%@ は Alive がインデックスを作成しているフォルダの外にあります。")
        case .addAsFolder: return ("Add as sample folder", "サンプルフォルダとして追加")
        case .alreadyInLibrary: return ("Already in the library", "すでにライブラリにあります")
        }
    }
}
