// Mac-only: Settings window and About page strings (en + ja).
import Foundation

enum SettingsStrings: LocalizedStrings {
    case tabGeneral, tabAbout
    case language, languageSystem
    case transparency, transparencyHelp
    case pluginSource, pluginSourceLive, pluginSourceFolders, pluginSourceHelp
    case dataFolder, openDataFolder
    case updatesTitle, updatesPlaceholder
    case version, versionDev, upstreamCommit, unknown
    case credit, linkUpstream, linkPort
    case disclaimer, trademarks
    case licenses, licenseUpstream, licenseMac, licenseMissing

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .tabGeneral: return ("General", "一般")
        case .tabAbout: return ("About", "情報")
        case .language: return ("Language", "言語")
        case .languageSystem: return ("System", "システム")
        case .transparency: return ("Transparent window", "ウィンドウを透明にする")
        case .transparencyHelp: return ("Blurs what is behind the window, like upstream's glass.",
                                        "ウィンドウの背後をぼかします（オリジナルのグラス効果）。")
        case .pluginSource: return ("Plugin list source", "プラグイン一覧の取得元")
        case .pluginSourceLive: return ("Live's plugin database", "Live のプラグインデータベース")
        case .pluginSourceFolders: return ("Plugin folders", "プラグインフォルダ")
        case .pluginSourceHelp: return ("Where the Plugins tab gets the list of installed plugins.",
                                        "プラグインタブでインストール済みプラグインを取得する場所です。")
        case .dataFolder: return ("Data folder", "データフォルダ")
        case .openDataFolder: return ("Open Data Folder", "データフォルダを開く")
        case .updatesTitle: return ("Updates", "アップデート")
        case .updatesPlaceholder: return ("Update checks are not available yet.",
                                          "アップデートの確認はまだ利用できません。")
        case .version: return ("Version %@", "バージョン %@")
        case .versionDev: return ("dev", "dev")
        case .upstreamCommit: return ("Based on upstream commit %@", "ベースとなるオリジナルのコミット: %@")
        case .unknown: return ("unknown", "不明")
        case .credit: return ("A macOS port of Alive by RueBlose", "RueBlose 作 Alive の macOS 版ポート")
        case .linkUpstream: return ("Alive on GitHub", "Alive (GitHub)")
        case .linkPort: return ("Alive for Mac on GitHub", "Alive for Mac (GitHub)")
        case .disclaimer: return ("This is an unofficial port. It is not made, reviewed or endorsed by the original author.",
                                  "これは非公式のポートです。オリジナルの作者による制作・確認・承認はありません。")
        case .trademarks: return ("Ableton, Live, Max for Live and Push are trademarks of Ableton AG. VST is a trademark of Steinberg Media Technologies GmbH. Audio Units, macOS and Finder are trademarks of Apple Inc. This project is not affiliated with, sponsored by or endorsed by any of them.",
                                  "Ableton、Live、Max for Live、Push は Ableton AG の商標です。VST は Steinberg Media Technologies GmbH の商標です。Audio Units、macOS、Finder は Apple Inc. の商標です。本プロジェクトはこれらの企業とは無関係であり、後援・承認を受けていません。")
        case .licenses: return ("Licenses", "ライセンス")
        case .licenseUpstream: return ("Alive (original)", "Alive（オリジナル）")
        case .licenseMac: return ("Alive for Mac", "Alive for Mac")
        case .licenseMissing: return ("The license text is included in the app bundle. When running from source, see the LICENSE and macos/LICENSE files in the repository.",
                                      "ライセンス全文はアプリ内に含まれています。ソースから実行している場合は、リポジトリの LICENSE と macos/LICENSE を参照してください。")
        }
    }
}
