// Mac-only: strings of the Mac integration (Spotlight, menu bar extra, Finder tags). en + ja.
import Foundation

enum IntegrationStrings: LocalizedStrings {
    // Settings section
    case sectionTitle
    case spotlightToggle, spotlightHelp
    case menuBarToggle, menuBarHelp
    case finderTagsToggle, finderTagsHelp
    // Spotlight item text
    case itemTracks, itemLive
    // Menu bar extra
    case menuBarTitle
    case todaySaves, streakDays, noActivity
    case pinned, recent, nowPlaying, noProjects
    case openInLive, showInAlive, play, pause
    case rescan, scanning, openAlive, quit
    // Help
    case helpTitle, helpMenuBar, helpSpotlight

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .sectionTitle: return ("Mac integration", "Mac 連携")
        case .spotlightToggle: return ("Search sets in Spotlight", "Spotlight で検索できるようにする")
        case .spotlightHelp: return ("Find sets in Spotlight by name, tempo, key, plugin or tag.",
                                     "セット名・テンポ・キー・プラグイン・タグで Spotlight から探せます")
        case .menuBarToggle: return ("Show Alive in the menu bar", "メニューバーに Alive を表示する")
        case .menuBarHelp: return ("Today's saves, pinned and recent projects and playback, one click away.",
                                   "今日の保存数、ピン留めと最近のプロジェクト、再生をワンクリックで操作できます。")
        case .finderTagsToggle: return ("Write tags as Finder tags", "タグを Finder タグとして書き込む")
        case .finderTagsHelp: return ("Alive's tags are written to the project folders as Finder tags. Folders in Dropbox or iCloud Drive sync these changes to your other devices. Finder tags you added yourself are kept.",
                                      "Alive のタグをプロジェクトフォルダに Finder タグとして書き込みます。Dropbox や iCloud Drive 内のフォルダでは、この変更が他のデバイスにも同期されます。ご自身で付けた Finder タグはそのまま残ります。")
        case .itemTracks: return ("%lld tracks", "%lld トラック")
        case .itemLive: return ("Live %@", "Live %@")
        case .menuBarTitle: return ("Alive", "Alive")
        case .todaySaves: return ("Saves today: %lld", "今日の保存: %lld 回")
        case .streakDays: return ("Streak: %lld days", "連続: %lld 日")
        case .noActivity: return ("No saves yet today", "今日はまだ保存していません")
        case .pinned: return ("Pinned", "ピン留め")
        case .recent: return ("Recent projects", "最近のプロジェクト")
        case .nowPlaying: return ("Now playing", "再生中")
        case .noProjects: return ("No projects yet", "プロジェクトはまだありません")
        case .openInLive: return ("Open in Live", "Live で開く")
        case .showInAlive: return ("Show in Alive", "Alive で表示")
        case .play: return ("Play", "再生")
        case .pause: return ("Pause", "一時停止")
        case .rescan: return ("Rescan", "再スキャン")
        case .scanning: return ("Scanning…", "スキャン中…")
        case .openAlive: return ("Open Alive", "Alive を開く")
        case .quit: return ("Quit Alive", "Alive を終了")
        case .helpTitle: return ("Mac integration", "Mac 連携")
        case .helpMenuBar: return ("The menu bar icon shows today's saves, pinned and recent projects and what is playing.",
                                   "メニューバーのアイコンから、今日の保存数、ピン留めと最近のプロジェクト、再生中の曲を確認できます。")
        case .helpSpotlight: return ("Spotlight finds your sets by name, tempo, key, plugin and tag. Turn it off in Settings.",
                                     "Spotlight でセット名・テンポ・キー・プラグイン・タグから探せます。設定でオフにできます。")
        }
    }
}
