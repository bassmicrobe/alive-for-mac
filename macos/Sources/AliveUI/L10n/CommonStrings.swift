// Mac-only: shell, menu, toolbar and shared words (en + ja).
import AliveCore
import Foundation

enum CommonStrings: LocalizedStrings {
    case appName
    // Tabs and windows
    case tabHome, tabSets, tabPlugins, tabSamples, tabStat
    case windowStat, windowPlayer
    // Toolbar
    case filters, searchIn, shownCount, shownProjects, scanFolders, foldersLabel, clearSearch, settings, help
    // Accessibility state values (VoiceOver)
    case setReadFailed
    case stateExpanded, stateCollapsed, stateOn, stateOff, dismiss
    // Menus
    case menuSet
    case openInLive, showInFinder, pin, tagsAndNotes, rescue, exportSet
    case arrangementPreview, playPause, launchLive, rescan, focusSearch
    // Shared words
    case close, cancel, done, ok, remove, reveal
    case comingSoonTitle, comingSoonBody
    // Toasts
    case liveNotFound, liveOpenFailed, liveLaunchFailed, audioFailed, folderOpenFailed
    case pathMissing, settingsSaveFailed, dataFileBackedUp, rootAdded, rootsAdded, alreadyWatching, notAFolder
    // Scan status and first run
    case scanning, scanProgress
    case emptyRootsTitle, emptyRootsBody, addProjectsFolder, chooseFolderPrompt, chooseFolderMessage
    case suggestionsTitle, addSuggestion, noSetsTitle, noSetsBody
    case catalogReadFailedTitle, catalogReadFailedBody, catalogUnreadableFolders
    case catalogRetainedNotice, catalogPartialNotice

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
        case .shownProjects: return ("%lld projects shown", "%lld 件のプロジェクトを表示")
        case .foldersLabel: return ("Folders", "フォルダ")
        case .clearSearch: return ("Clear search", "検索をクリア")
        case .setReadFailed: return ("This set could not be read. See alive.log for details.",
                                     "このセットを読み込めませんでした。詳細は alive.log を確認してください。")
        case .stateExpanded: return ("Expanded", "展開済み")
        case .stateCollapsed: return ("Collapsed", "折りたたみ")
        case .stateOn: return ("On", "オン")
        case .stateOff: return ("Off", "オフ")
        case .dismiss: return ("Dismiss", "閉じる")
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
        case .settingsSaveFailed: return ("Could not save settings: %@", "設定を保存できませんでした: %@")
        case .dataFileBackedUp:
            return ("“%1$@” was not a plain UTF-8 text file. The original was kept as “%1$@.bak”.",
                    "「%1$@」は通常の UTF-8 テキストではありませんでした。元のファイルは「%1$@.bak」として残してあります。")
        case .rootAdded: return ("Added %@", "%@を追加しました")
        case .rootsAdded: return ("Added %lld folders", "%lld 個のフォルダを追加しました")
        case .alreadyWatching: return ("Already watching that folder", "そのフォルダはすでに監視しています")
        case .notAFolder: return ("Not a folder: %@", "フォルダではありません: %@")

        case .scanning: return ("Scanning…", "スキャン中…")
        case .scanProgress: return ("Scanning %1$lld / %2$lld", "スキャン中 %1$lld / %2$lld")
        case .emptyRootsTitle: return ("Nothing to show yet", "まだ表示するものがありません")
        case .emptyRootsBody: return ("Alive reads your Live sets from the folders you point it at. It only reads; it never changes a set.",
                                      "Alive は指定したフォルダの Live セットを読み込みます。読み取り専用で、セットは変更しません。")
        case .addProjectsFolder: return ("Add the folder with your Live projects", "Live プロジェクトのフォルダを追加")
        case .chooseFolderPrompt: return ("Add", "追加")
        case .chooseFolderMessage: return ("Choose the folders that contain your Live projects", "Live プロジェクトが入っているフォルダを選択")
        case .suggestionsTitle: return ("Found on this Mac", "この Mac で見つかりました")
        case .addSuggestion: return ("Add", "追加")
        case .noSetsTitle: return ("No sets found", "セットが見つかりません")
        case .noSetsBody: return ("No Live sets were found in the configured folders. Choose the folders that contain your .als files with Scan Folders (⇧⌘O).",
                                  "設定したフォルダから Live セットが見つかりませんでした。スキャンするフォルダ（⇧⌘O）で .als ファイルが入ったフォルダを指定してください。")
        case .catalogReadFailedTitle: return ("Some folders could not be read", "読み込めないフォルダがあります")
        case .catalogReadFailedBody:
            return ("Check that these folders are available and readable, then rescan. You can change the project folders with Scan Folders (⇧⌘O).",
                    "フォルダの接続状態と読み取り権限を確認して、再スキャンしてください。スキャンするフォルダ（⇧⌘O）でプロジェクトのフォルダを変更できます。")
        case .catalogUnreadableFolders: return ("%lld folders could not be read", "%lld 個のフォルダを読み込めませんでした")
        case .catalogRetainedNotice:
            return ("Some project folders could not be read. Showing the previous catalog; it may be outdated.",
                    "一部のプロジェクトフォルダを読み込めませんでした。前回のカタログを表示しています（最新の状態とは異なる場合があります）。")
        case .catalogPartialNotice:
            return ("Some project folders could not be read. The catalog may be incomplete.",
                    "一部のプロジェクトフォルダを読み込めませんでした。カタログに含まれていないセットがある可能性があります。")
        }
    }
}

/// A set that could not be read shows the same plain sentence everywhere; the parser's own
/// wording (English, technical) goes to alive.log once per set and message instead.
enum ReadErrorLog {
    private static let lock = NSLock()
    private static var seen = Set<String>()

    /// Logs `raw` for `path` the first time it is seen and returns the sentence to show.
    @discardableResult
    static func note(_ raw: String, of path: String) -> String {
        lock.lock()
        let isNew = seen.insert(path + "|" + raw).inserted
        lock.unlock()
        if isNew { Diag.warn("could not read \(path): \(raw)") }
        return CommonStrings.setReadFailed.s
    }
}
