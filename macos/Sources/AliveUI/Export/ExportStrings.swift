// Mac-only: string table for the Export sheet (upstream CollectDialog texts). Every case needs
// en + ja; format arguments are positional.
import Foundation

enum ExportStrings: LocalizedStrings {
    case title, titleFor
    case counting, cannotRead
    // The four questions of "Collect All and Save" and the always-copied line
    case rowElsewhere, rowOtherProjects, rowUserLibrary, rowFactoryPacks, inProject
    case filesOne, filesMany
    case willCopy, notEnoughSpace, addToZip
    case destination, chooseDestination, panelMessage, panelPrompt, folderMode, zipMode
    // Buttons
    case export, cancel, cancelling, close, showInFinder
    // Progress
    case exporting, writingSet, packing
    // Grouped notices (one line each, the list behind a disclosure)
    case notFoundSummary, failedSummary, showList, hideList, listItem
    // Outcome
    case done, doneWithFailures, toastDone
    // Errors (one inline message, never one per file)
    case errDestinationExists, errNotEnoughSpace, errPack, errSetNotWritten, errIO, errCancelled

    var en: String { text.en }
    var ja: String { text.ja }

    /// "1 file" / "12 files".
    static func files(_ n: Int) -> String {
        n == 1 ? filesOne.f(n) : filesMany.f(n)
    }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Export", "エクスポート")
        case .titleFor: return ("Export: %@", "エクスポート: %@")
        case .counting: return ("Counting…", "集計中…")
        case .cannotRead: return ("Cannot read this set: %@", "このセットを読み込めません: %@")
        case .rowElsewhere: return ("Files from elsewhere", "その他の場所のファイル")
        case .rowOtherProjects: return ("Files from other Projects", "他のプロジェクトのファイル")
        case .rowUserLibrary: return ("Files from User Library", "ユーザーライブラリのファイル")
        case .rowFactoryPacks: return ("Files from Factory Packs", "ファクトリーパックのファイル")
        case .inProject: return ("In project (always copied)", "プロジェクト内（常にコピー）")
        case .filesOne: return ("%lld file", "%lld ファイル")
        case .filesMany: return ("%lld files", "%lld ファイル")
        case .willCopy: return ("Will copy %1$@, %2$@", "%1$@、%2$@をコピーします")
        case .notEnoughSpace: return ("Not enough space", "空き容量が足りません")
        case .addToZip: return ("Add to ZIP", "ZIP にまとめる")
        case .destination: return ("Destination", "保存先")
        case .chooseDestination: return ("Choose…", "選択…")
        case .panelMessage:
            return ("Choose where the collected project is created. Nothing existing is replaced.",
                    "収集したプロジェクトの作成先を選んでください。既存のものは置き換えられません。")
        case .panelPrompt: return ("Choose", "選択")
        case .folderMode: return ("Folder", "フォルダ")
        case .zipMode: return ("ZIP archive", "ZIP アーカイブ")
        case .export: return ("Export", "エクスポート")
        case .cancel: return ("Cancel", "キャンセル")
        case .cancelling: return ("Cancelling…", "中止しています…")
        case .close: return ("Close", "閉じる")
        case .showInFinder: return ("Show in Finder", "Finder に表示")
        case .exporting: return ("Exporting %1$lld of %2$lld", "エクスポート中 %1$lld / %2$lld")
        case .writingSet: return ("Writing the collected set…", "収集したセットを書き込み中…")
        case .packing: return ("Packing the archive…", "アーカイブを作成中…")
        case .notFoundSummary:
            return ("%@ not found — left as they are", "%@が見つかりません。そのまま残します")
        case .failedSummary:
            return ("%@ could not be copied — their references were left as they were",
                    "%@をコピーできませんでした。参照は元のままです")
        case .showList: return ("Show list", "一覧を表示")
        case .hideList: return ("Hide list", "一覧を隠す")
        case .listItem: return ("%1$@ — %2$@", "%1$@ — %2$@")
        case .done: return ("Exported %1$@ to “%2$@”", "%1$@を「%2$@」にエクスポートしました")
        case .doneWithFailures:
            return ("Exported %1$@ to “%2$@”, but some files could not be copied", "%1$@を「%2$@」にエクスポートしましたが、一部のファイルはコピーできませんでした")
        case .toastDone: return ("Exported “%@”", "「%@」をエクスポートしました")
        case .errDestinationExists:
            return ("“%@” already exists. Choose another name — nothing is ever replaced.",
                    "「%@」は既に存在します。別の名前を選んでください。既存のものは置き換えません。")
        case .errNotEnoughSpace:
            return ("Not enough space: %1$@ needed, %2$@ free.", "空き容量が足りません: %1$@ 必要、空き %2$@。")
        case .errPack: return ("Could not pack the archive: %@", "アーカイブを作成できません: %@")
        case .errSetNotWritten: return ("Could not write the collected set: %@", "収集したセットを書き込めません: %@")
        case .errIO: return ("Could not export: %@", "エクスポートできません: %@")
        case .errCancelled: return ("Export cancelled — nothing was left behind.", "エクスポートを中止しました。何も残っていません。")
        }
    }
}
