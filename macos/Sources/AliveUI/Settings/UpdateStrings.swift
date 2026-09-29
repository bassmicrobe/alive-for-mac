// Mac-only: string table for the update check (upstream: the literals in src/SettingsDialog.cs and
// src/UpdateCheck.cs). The section's own title stays `SettingsStrings.updatesTitle`.
import Foundation

enum UpdateStrings: LocalizedStrings {
    case currentVersion, developmentBuild
    case checkButton, openRelease, checking
    case upToDate, newerVersion, newerVersionNamed, noReleases
    case failedRateLimited, failedUnreachable, failedUnexpected
    case dailyToggle, dailyHelp
    case lastChecked, neverChecked

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .currentVersion: return ("Alive for Mac %@", "Alive for Mac %@")
        case .developmentBuild: return ("Alive for Mac (development build)", "Alive for Mac（開発ビルド）")
        case .checkButton: return ("Check for updates", "アップデートを確認")
        case .openRelease: return ("Open release page", "リリースページを開く")
        case .checking: return ("Checking…", "確認中…")
        case .upToDate: return ("You have the latest version", "最新バージョンです")
        case .newerVersion: return ("Version %@ is available", "バージョン %@ が利用できます")
        case .newerVersionNamed: return ("Version %1$@ is available: %2$@", "バージョン %1$@ が利用できます: %2$@")
        case .noReleases: return ("No releases have been published yet", "公開されたリリースはまだありません")
        case .failedRateLimited: return ("GitHub is rate-limiting this address — try again later",
                                         "GitHub がこのアドレスからのアクセスを制限しています。しばらくしてからもう一度お試しください")
        case .failedUnreachable: return ("Could not reach GitHub", "GitHub に接続できませんでした")
        case .failedUnexpected: return ("GitHub answered something unexpected", "GitHub から想定外の応答がありました")
        case .dailyToggle: return ("Check for updates once a day", "1日1回アップデートを確認する")
        case .dailyHelp: return ("Alive goes online only when you ask, or once a day if this is on. Only a public page is requested; nothing about you or your library is sent.",
                                 "Alive は、確認を押したとき、またはこれをオンにしたときの1日1回だけ通信します。公開ページを取得するだけで、あなたやライブラリに関する情報は送信しません。")
        case .lastChecked: return ("Last checked: %@", "最終確認: %@")
        case .neverChecked: return ("Not checked yet", "まだ確認していません")
        }
    }
}
