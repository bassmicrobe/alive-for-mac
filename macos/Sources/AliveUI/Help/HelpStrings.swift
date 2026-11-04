// Mac-only: help sheet strings (port of the text in src/HelpOverlay.cs, with the Mac shortcuts).
import Foundation

enum HelpStrings: LocalizedStrings {
    case title, shortcuts, tabsTitle
    case groupNavigation, groupSets, groupPreview, groupSamples, groupPlayback, groupGeneral
    // Tab descriptions
    case aboutHome, aboutSets, aboutPlugins, aboutSamples
    // Shortcut actions
    case goHome, goSets, goPlugins, goSamples, openStat, focusSearch, openFilters
    case scanFolders, rescan
    case openInLive, showInFinder, pinSet, tagsAndNotes, rescueSet, exportSet
    case playPause, arrangementPreview
    case launchLive, openSettings, openHelp, fullscreen, minimize, quit
    case listReturn, listSpace, searchIntoResults, listEnds
    case previewWheel, previewShiftWheel, previewCommandWheel, previewOptionWheel, previewMiddleDrag, previewZoomKeys
    // Caps that are not keys
    case keyWheel, keyMiddleDrag, keyClick
    case sampleAudition, samplePlay, sampleCollapse, sampleEmptyClick, sampleOpen, sampleReveal, playerReveal

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Alive for Mac Help", "Alive for Mac ヘルプ")
        case .shortcuts: return ("Keyboard Shortcuts", "キーボードショートカット")
        case .tabsTitle: return ("What the tabs show", "各タブの内容")
        case .groupNavigation: return ("Navigation", "ナビゲーション")
        case .groupSets: return ("Sets", "セット")
        case .groupPreview: return ("Arrangement preview", "アレンジメントのプレビュー")
        case .groupSamples: return ("Samples", "サンプル")
        case .groupPlayback: return ("Playback", "再生")
        case .groupGeneral: return ("General", "一般")

        case .aboutHome: return ("Pinned sets, recent renders and a year of activity; click a day to see what was saved that day.",
                                 "ピン留めしたセット、最近のレンダー、1 年分のアクティビティ。日をクリックすると、その日に保存したプロジェクトを表示します。")
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
        case .exportSet: return ("Export a set with everything it uses", "セットを使用ファイルごとエクスポート")

        case .playPause: return ("Play / pause render or sample", "レンダー・サンプルの再生 / 一時停止")
        case .arrangementPreview: return ("Arrangement preview", "アレンジメントのプレビュー")

        case .launchLive: return ("Launch Live", "Live を起動")
        case .openSettings: return ("Settings", "設定")
        case .openHelp: return ("Help", "ヘルプ")
        case .fullscreen: return ("Full screen", "フルスクリーン")
        case .minimize: return ("Minimize", "しまう")
        case .quit: return ("Quit", "終了")
        case .listReturn: return ("Open the selected set", "選択したセットを開く")
        case .sampleAudition: return ("Play or stop the sample", "サンプルを再生 / 停止")
        case .samplePlay: return ("Play the sample from the start / open the folder", "サンプルを頭から再生 / フォルダを開く")
        case .sampleCollapse: return ("Close the folder / go to the parent", "フォルダを閉じる / 親フォルダへ")
        case .sampleEmptyClick: return ("Stop the sample (click on empty space)", "サンプルを停止（何もない所をクリック）")
        case .sampleOpen: return ("Open a folder / show a sample in the tree", "フォルダを開く / サンプルをツリーで表示")
        case .sampleReveal: return ("Show the sample in Finder", "サンプルを Finder に表示")
        case .listSpace: return ("Play / pause the render (also on the Plugins tab)", "レンダーを再生 / 一時停止（プラグインタブでも）")
        case .searchIntoResults: return ("From the search field into the results", "検索欄から結果へ移動")
        case .listEnds: return ("First or last item of the list", "リストの先頭 / 末尾の項目")
        case .previewWheel: return ("Scroll the tracks", "トラックをスクロール")
        case .previewShiftWheel: return ("Move along the time", "時間方向に移動")
        case .previewCommandWheel: return ("Zoom the time (a pinch does too)", "時間方向にズーム（ピンチも可）")
        case .previewOptionWheel: return ("Make the tracks taller or lower", "トラックの高さを変更")
        case .previewMiddleDrag: return ("Move both ways", "上下左右に移動")
        case .previewZoomKeys: return ("Zoom in / out / the whole song", "拡大 / 縮小 / 全体表示")
        case .keyWheel: return ("Wheel", "ホイール")
        case .keyMiddleDrag: return ("Middle drag", "中ボタンドラッグ")
        case .keyClick: return ("Click", "クリック")
        case .playerReveal: return ("In the player: show the render in Finder", "プレーヤー: レンダーを Finder に表示")
        }
    }
}
