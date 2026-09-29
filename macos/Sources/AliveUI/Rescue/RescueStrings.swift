// Mac-only: string table for the Rescue sheet (upstream RescueDialog texts). Every case needs
// en + ja; format arguments are positional.
import Foundation

enum RescueStrings: LocalizedStrings {
    // Header and states
    case title, titleFor
    case loading
    case readError, noPlugins, logNone
    case logLoaded, logStops, logUnfinished, logCrashed
    case refusedSummary, refusedShow, refusedHide, refusedLine
    // Checklist
    case listLabel, listUnidentified, allOff, allOn, suggested, noteSuspect, noteBreaks
    // Buttons
    case openProbe, nextProbe, probeAgain, waiting, close, saveRescued, didOpen, didNotOpen
    // Hints
    case hintWaiting, hintCloseLive, hintUntick, hintProbe
    // Progress
    case statusStarted, statusLoading, statusOpened, statusNotOpened, stoppedInside
    case statusNeverOpened, statusStartFailed, statusSaved, statusSaveFailed
    // Verdicts and descriptions
    case verdictCulprit, verdictGroup, verdictNotPlugins
    case describeNothing, pluginsMany, pluginOne
    case toastSaved, errNotFoundInSet, errNothingToDisable

    var en: String { text.en }
    var ja: String { text.ja }

    /// "1 plugin" / "12 plugins".
    static func plugins(_ n: Int) -> String {
        n == 1 ? pluginOne.f(n) : pluginsMany.f(n)
    }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Rescue", "レスキュー")
        case .titleFor: return ("Rescue: %@", "レスキュー: %@")
        case .loading: return ("Reading the set and Live's log…", "セットと Live のログを読み込み中…")
        case .readError:
            return ("This .als cannot be read at all: %@. That is damage to the file itself, not a plugin problem.",
                    "この .als は読み込めません: %@。プラグインではなく、ファイル自体の破損です。")
        case .noPlugins:
            return ("This set has no third-party plugins — there is nothing here to switch off. Whatever stops it from opening is somewhere else.",
                    "このセットにはサードパーティ製プラグインがないため、オフにできるものがありません。開けない原因は別の場所にあります。")
        case .logNone:
            return ("Live's log has no record of this set. Untick a plugin to test it, or click “All Off” to disable everything at once.",
                    "Live のログにこのセットの記録はありません。プラグインのチェックを外して試すか、「すべてオフ」で一度に無効にしてください。")
        case .logLoaded:
            return ("Live's log says this set opened normally on %1$@, with %2$@ restored. If it fails now, something changed since — a plugin update, most likely.",
                    "Live のログでは、このセットは %1$@ に正常に開き、%2$@が復元されました。今開けないなら、その後に何かが変わっています（多くはプラグインのアップデート）。")
        case .logStops:
            return ("Live's log stops inside %1$@ %2$@ on %3$@ — it restored %4$@ and never came back from that one. Untick it below and probe.",
                    "Live のログは %3$@ に %1$@ %2$@ の中で止まっています。%4$@を復元した後、そこから戻りませんでした。下でチェックを外してプローブしてください。")
        case .logUnfinished:
            return ("Live's log has an unfinished attempt from %@, with no plugin left pending — the set may be breaking before the plugins get their turn.",
                    "Live のログに %@ の未完了の試行があります。保留中のプラグインはなく、プラグインの前にセットが壊れている可能性があります。")
        case .logCrashed:
            return ("Live reported a crash the next time it started.", "Live は次の起動時にクラッシュを検出しました。")
        case .refusedSummary:
            return ("%@ failed to load in that attempt", "その試行で%@の読み込みに失敗しました")
        case .refusedShow: return ("Show list", "一覧を表示")
        case .refusedHide: return ("Hide list", "一覧を隠す")
        case .refusedLine: return ("%1$@ %2$@ ×%3$lld", "%1$@ %2$@ ×%3$lld")
        case .listLabel: return ("Third-party plugins (%lld)", "サードパーティ製プラグイン (%lld)")
        case .listUnidentified: return ("%lld more cannot be identified", "ほか %lld 個は識別できません")
        case .allOff: return ("All Off", "すべてオフ")
        case .allOn: return ("All On", "すべてオン")
        case .suggested: return ("Suggested", "おすすめ")
        case .noteSuspect: return ("suspect", "疑わしい")
        case .noteBreaks: return ("BREAKS THE SET", "原因")
        case .openProbe: return ("Open probe in Live", "プローブを Live で開く")
        case .nextProbe: return ("Next probe", "次のプローブ")
        case .probeAgain: return ("Probe again", "もう一度プローブ")
        case .waiting: return ("Waiting for Live…", "Live を待っています…")
        case .close: return ("Close", "閉じる")
        case .saveRescued: return ("Save rescued copy", "救出コピーを保存")
        case .didOpen: return ("It opened", "開けた")
        case .didNotOpen: return ("It didn't open", "開けなかった")
        case .hintWaiting:
            return ("Live is opening the probe. Watch it, then close Live — the answer is read from Live's own log. Or answer yourself below.",
                    "Live がプローブを開いています。結果を確認して Live を閉じてください。答えは Live のログから読み取られます。下で自分で答えることもできます。")
        case .hintCloseLive:
            return ("Close Ableton Live first — if the probe crashes it would take your open project with it.",
                    "先に Ableton Live を閉じてください。プローブがクラッシュすると、開いているプロジェクトも巻き込まれます。")
        case .hintUntick:
            return ("Untick the plugins you want to switch off in the probe.",
                    "プローブでオフにするプラグインのチェックを外してください。")
        case .hintProbe:
            return ("The probe is a copy — “%@” next to the original. Your set is never modified. Do not save the probe from Live.",
                    "プローブはコピーです。元のセットの隣に「%@」として作られ、元のセットは変更されません。Live からプローブを保存しないでください。")
        case .statusStarted:
            return ("Probe %1$lld: %2$@ disabled. Waiting for Live to open it…",
                    "プローブ %1$lld: %2$@を無効化。Live が開くのを待っています…")
        case .statusLoading:
            return ("Probe %1$lld: Live is loading it — %2$@ restored so far…",
                    "プローブ %1$lld: Live が読み込み中です。ここまでに%2$@を復元…")
        case .statusOpened:
            return ("Probe %1$lld opened. The culprit is among the %2$@ it had switched off. Close Live and run the next probe.",
                    "プローブ %1$lld は開けました。原因はオフにした%2$@の中にあります。Live を閉じて次のプローブを実行してください。")
        case .statusNotOpened:
            return ("Probe %1$lld did not open%2$@ — the culprit was still enabled. %3$@ left to check. Close Live and run the next probe.",
                    "プローブ %1$lld は開けませんでした%2$@。原因は有効なままのプラグインにあります。残り%3$@。Live を閉じて次のプローブを実行してください。")
        case .stoppedInside: return (" (Live stopped inside %@)", "（Live は %@ の中で停止）")
        case .statusNeverOpened:
            return ("Live never opened the probe. Try again — or open it by hand from the project folder.",
                    "Live がプローブを開きませんでした。もう一度試すか、プロジェクトフォルダから手動で開いてください。")
        case .statusStartFailed: return ("Could not start the probe: %@", "プローブを開始できません: %@")
        case .statusSaved:
            return ("Saved “%1$@”. It is your set with %2$@ disabled — everything else, automation included, is untouched. The original is unchanged.",
                    "「%1$@」を保存しました。%2$@を無効にしたセットで、オートメーションを含むそれ以外は手を加えていません。元のセットは変更されていません。")
        case .statusSaveFailed: return ("Could not save the copy: %@", "コピーを保存できません: %@")
        case .verdictCulprit: return ("%1$@ %2$@ breaks this set.", "%1$@ %2$@ がこのセットを壊しています。")
        case .verdictGroup:
            return ("More than one plugin is involved. Disabling %@ opens the set.",
                    "複数のプラグインが関わっています。%@を無効にするとセットが開きます。")
        case .verdictNotPlugins:
            return ("Not a plugin problem — the set fails with every third-party plugin disabled.",
                    "プラグインの問題ではありません。サードパーティ製プラグインをすべて無効にしても開けません。")
        case .describeNothing: return ("nothing", "なし")
        case .pluginsMany: return ("%lld plugins", "%lld 個のプラグイン")
        case .pluginOne: return ("%lld plugin", "%lld 個のプラグイン")
        case .toastSaved: return ("Saved “%@”", "「%@」を保存しました")
        case .errNotFoundInSet:
            return ("None of those plugins were found inside the set.", "選んだプラグインはセット内に見つかりませんでした。")
        case .errNothingToDisable:
            return ("Pick at least one plugin to disable.", "無効にするプラグインを1つ以上選んでください。")
        }
    }
}
