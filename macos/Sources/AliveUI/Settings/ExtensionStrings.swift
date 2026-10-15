// Mac-only: string table for the Quick Look / widget settings section and the alive:// URL replies.
import Foundation

enum ExtensionStrings: LocalizedStrings {
    case title, quickLook, widget
    case stateEnabled, stateDisabled, stateNotInstalled, stateChecking, stateEnabling, stateCheckFailed
    case enable, enableExtension, recheck, recheckAccessibility
    case enableFailed, noFailureDetails, notInstalledHint
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
        case .stateNotInstalled: return ("Not registered", "未登録")
        case .stateChecking: return ("Checking…", "確認中…")
        case .stateEnabling: return ("Enabling…", "有効にしています…")
        case .stateCheckFailed: return ("Could not check status", "状態を確認できませんでした")
        case .enable: return ("Enable", "有効にする")
        case .enableExtension: return ("Enable %@", "%@を有効にする")
        case .recheck: return ("Check again", "再確認")
        case .recheckAccessibility: return ("Check extension status again", "拡張機能の状態を再確認")
        case .enableFailed: return ("Could not enable it: %@", "有効にできませんでした: %@")
        case .noFailureDetails: return ("macOS did not provide details. Check the status again.",
                                        "macOS から詳細が返されませんでした。状態を再確認してください。")
        case .notInstalledHint: return ("macOS has not registered the extension. Put the app in /Applications, launch it, then check again.",
                                        "macOS に拡張機能が登録されていません。アプリを /Applications に置いて起動し、再確認してください。")
        case .quickLookHowTo: return ("In Finder, select an .als file and press Space.",
                                      "Finder で .als ファイルを選び、スペースキーを押します。")
        case .widgetHowTo: return ("Right-click the desktop, choose Edit Widgets, then pick Alive.",
                                   "デスクトップを右クリック →「ウィジェットを編集」で Alive を選びます。")
        case .urlNotInCatalog: return ("Not a set in the catalog: %@", "カタログにないセットです: %@")
        case .urlEmptyCatalog: return ("The catalog has no sets yet.", "カタログにセットがありません。")
        }
    }
}
