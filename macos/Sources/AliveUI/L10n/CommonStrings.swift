// Mac-only: shell, menu, toolbar and shared words (en + ja).
import Foundation

enum CommonStrings: LocalizedStrings {
    case appName
    // Tabs and windows
    case tabHome, tabSets, tabPlugins, tabSamples, tabStat
    case windowStat, windowPlayer
    // Toolbar
    case filters, searchIn, shownCount, scanFolders, settings, help
    // Menus
    case menuSet
    case openInLive, showInFinder, pin, tagsAndNotes, rescue, exportSet
    case arrangementPreview, playPause, launchLive, rescan, focusSearch
    // Shared words
    case close, cancel, done, ok, remove, reveal
    case comingSoonTitle, comingSoonBody
    // Toasts
    case liveNotFound, liveOpenFailed, liveLaunchFailed, audioFailed, folderOpenFailed
    case pathMissing

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .appName: return ("Alive for Mac", "Alive for Mac")
        case .tabHome: return ("Home", "ホーム")
        case .tabSets: return ("Sets", "セット")
        case .tabPlugins: return ("Plugins", "プラグイン")
        case .tabSamples: return ("Samples", "サンプル")
        case .tabStat: return ("Stat", "統計")
        case .windowStat: return ("Alive Stat", "Alive 統計")
        case .windowPlayer: return ("Player", "プレーヤー")

        case .filters: return ("Filters", "フィルター")
        case .searchIn: return ("Search in %@…", "%@を検索…")
        case .shownCount: return ("%lld shown", "%lld 件を表示")
        case .scanFolders: return ("Scan Folders…", "スキャンするフォルダ…")
        case .settings: return ("Settings", "設定")
        case .help: return ("Help", "ヘルプ")

        case .menuSet: return ("Set", "セット")
        case .openInLive: return ("Open in Live", "Live で開く")
        case .showInFinder: return ("Show in Finder", "Finder に表示")
        case .pin: return ("Pin / Unpin", "ピン留め / 解除")
        case .tagsAndNotes: return ("Tags and Notes…", "タグとメモ…")
        case .rescue: return ("Rescue…", "レスキュー…")
        case .exportSet: return ("Export…", "エクスポート…")
        case .arrangementPreview: return ("Arrangement Preview", "アレンジメントのプレビュー")
        case .playPause: return ("Play / Pause", "再生 / 一時停止")
        case .launchLive: return ("Launch Live", "Live を起動")
        case .rescan: return ("Rescan", "再スキャン")
        case .focusSearch: return ("Search", "検索")

        case .close: return ("Close", "閉じる")
        case .cancel: return ("Cancel", "キャンセル")
        case .done: return ("Done", "完了")
        case .ok: return ("OK", "OK")
        case .remove: return ("Remove", "削除")
        case .reveal: return ("Reveal", "表示")
        case .comingSoonTitle: return ("Coming soon", "近日対応")
        case .comingSoonBody: return ("This part of Alive for Mac is not ready yet.",
                                       "この機能はまだ準備中です。")

        case .liveNotFound: return ("Ableton Live is not installed.", "Ableton Live が見つかりません。")
        case .liveOpenFailed: return ("Could not open the set in Live: %@", "Live でセットを開けませんでした: %@")
        case .liveLaunchFailed: return ("Could not launch Live: %@", "Live を起動できませんでした: %@")
        case .audioFailed: return ("Playback failed: %@", "再生に失敗しました: %@")
        case .folderOpenFailed: return ("Could not open the folder: %@", "フォルダを開けませんでした: %@")
        case .pathMissing: return ("The file no longer exists: %@", "ファイルが見つかりません: %@")
        }
    }
}
