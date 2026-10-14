// Mac-only: string table for the Quick Look / widget settings section and the alive:// URL replies.
import Foundation

enum ExtensionStrings: LocalizedStrings {
    case title, quickLook, widget
    case stateEnabled, stateDisabled, stateNotInstalled, stateChecking
    case enable, recheck
    case enableFailed, notInstalledHint
    case quickLookHowTo, widgetHowTo
    case urlNotInCatalog, urlEmptyCatalog

    var en: String { text.en }
    var ja: String { text.ja }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Quick Look & widget", "Quick Look とウィジェット")
        case .quickLook: return ("Quick Look preview", "Quick Look プレビュー")
        case .widget: return ("Desktop widget", "デスクトップウィジェット")
        case .stateEnabled: return ("Enabled", "有効")
        case .stateDisabled: return ("Not enabled", "無効")
        case .stateNotInstalled: return ("Not available", "利用できません")
        case .stateChecking: return ("Checking…", "確認中…")
        case .enable: return ("Enable", "有効にする")
        case .recheck: return ("Check again", "再確認")
        case .enableFailed: return ("Could not enable it: %@", "有効にできませんでした: %@")
        case .notInstalledHint: return ("They come with the app in /Applications; this build has none.",
                                        "アプリ（/Applications）に同梱されています。このビルドには含まれていません。")
        case .quickLookHowTo: return ("In Finder, select an .als file and press Space.",
                                      "Finder で .als ファイルを選び、スペースキーを押します。")
        case .widgetHowTo: return ("Right-click the desktop, choose Edit Widgets, then pick Alive.",
                                   "デスクトップを右クリック →「ウィジェットを編集」で Alive を選びます。")
        case .urlNotInCatalog: return ("Not a set in the catalog: %@", "カタログにないセットです: %@")
        case .urlEmptyCatalog: return ("The catalog has no sets yet.", "カタログにセットがありません。")
        }
    }
}
