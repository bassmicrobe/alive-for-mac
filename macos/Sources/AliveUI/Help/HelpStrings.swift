// Mac-only: help sheet strings (port of the text in src/HelpOverlay.cs, with the Mac shortcuts).
import Foundation

enum HelpStrings: LocalizedStrings {
    case title, shortcuts, tabsTitle
    case groupNavigation, groupSets, groupSamples, groupPlayback, groupGeneral
    // Tab descriptions
    case aboutHome, aboutSets, aboutPlugins, aboutSamples
    // Shortcut actions
    case goHome, goSets, goPlugins, goSamples, openStat, focusSearch, openFilters
    case scanFolders, rescan
    case openInLive, showInFinder, pinSet, tagsAndNotes, rescueSet, exportSet
    case playPause, arrangementPreview
    case launchLive, openSettings, openHelp, fullscreen, minimize, quit
    case listReturn, listSpace
    case sampleFolder, sampleAudition, sampleOpen, sampleReveal

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Alive for Mac Help", "Alive for Mac ヘルプ")
        case .shortcuts: return ("Keyboard Shortcuts", "キーボードショートカット")
        case .tabsTitle: return ("What the tabs show", "各タブの内容")
        case .groupNavigation: return ("Navigation", "ナビゲーション")
        case .groupSets: return ("Sets", "セット")
        case .groupSamples: return ("Samples", "サンプル")
        case .groupPlayback: return ("Playback", "再生")
        case .groupGeneral: return ("General", "一般")

        case .aboutHome: return ("Pinned sets, recent renders and a year of activity.",
                                 "ピン留めしたセット、最近のレンダー、1 年分のアクティビティ。")
        case .aboutSets: return ("Every Live set in your project folders, with tags, notes and details.",
                                 "プロジェクトフォルダ内のすべての Live セット。タグ、メモ、詳細付き。")
        case .aboutPlugins: return ("The plugins you have installed and which sets use them.",
                                    "インストール済みのプラグインと、それを使うセット。")
        case .aboutSamples: return ("Your sample folders, with audition and usage.",
                                    "サンプルフォルダ。試聴と使用状況を確認できます。")

        case .goHome: return ("Home", "ホーム")
        case .goSets: return ("Sets", "セット")
        case .goPlugins: return ("Plugins", "プラグイン")
        case .goSamples: return ("Samples", "サンプル")
        case .openStat: return ("Stat window", "統計ウィンドウ")
        case .focusSearch: return ("Search", "検索")
        case .openFilters: return ("Filters", "フィルター")
        case .scanFolders: return ("Scan folders", "スキャンするフォルダ")
        case .rescan: return ("Rescan", "再スキャン")

        case .openInLive: return ("Open set in Live", "セットを Live で開く")
        case .showInFinder: return ("Show in Finder", "Finder に表示")
        case .pinSet: return ("Pin set", "セットをピン留め")
        case .tagsAndNotes: return ("Tags and notes", "タグとメモ")
        case .rescueSet: return ("Rescue a set", "セットをレスキュー")
        case .exportSet: return ("Export (collect all)", "エクスポート（すべてを収集）")

        case .playPause: return ("Play / pause render or sample", "レンダー・サンプルの再生 / 一時停止")
        case .arrangementPreview: return ("Arrangement preview", "アレンジメントのプレビュー")

        case .launchLive: return ("Launch Live", "Live を起動")
        case .openSettings: return ("Settings", "設定")
        case .openHelp: return ("Help", "ヘルプ")
        case .fullscreen: return ("Full screen", "フルスクリーン")
        case .minimize: return ("Minimize", "しまう")
        case .quit: return ("Quit", "終了")
        case .listReturn: return ("Open the selected set", "選択したセットを開く")
        case .sampleFolder: return ("Collapse / expand the folder", "フォルダを閉じる / 開く")
        case .sampleAudition: return ("Audition the selected sample", "選択したサンプルを試聴")
        case .sampleOpen: return ("Open a folder / show a sample in the tree", "フォルダを開く / サンプルをツリーで表示")
        case .sampleReveal: return ("Show the sample in Finder", "サンプルを Finder に表示")
        case .listSpace: return ("Play / pause in a focused list", "リストで再生 / 一時停止")
        }
    }
}
