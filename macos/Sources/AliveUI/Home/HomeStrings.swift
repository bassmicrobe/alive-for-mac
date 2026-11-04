// Mac-only: string table for the Home feature — Home tab, arrangement pictures, preview sheet and
// the player window. Every case needs en + ja.
import Foundation

enum HomeStrings: LocalizedStrings {
    // Tab / sheet titles
    case title, previewTitle
    // Overview
    case readySets, readySetsHelp, readyProjectsOne, readyProjects
    case overview, activeDays, streak, noStreak, record, peakHour, onDisk
    case nothingSaved, saveOne, saveMany, daysShort, overviewCollapse, overviewExpand
    // A day of the calendar, clicked
    case dayNotRecorded, dayProjectGone
    // Projects
    case projects, shownProjectOne, shownProjectMany
    case pinnedFirstOn, pinnedFirstOff, nothingIndexed, noMatches
    case newLiveSet, newLiveSetHelp, noArrangement, thumbUnreadable
    case playRender, pauseRender, openPlayer, pinProject, unpin, showDetails, pinnedBadge
    // Now playing strip
    case nowPlayingSeek, stopPlayback, showSet
    // Arrangement preview
    case previewReading, previewEmpty, previewBPM, previewBars, previewTracks, previewClips
    case previewBarOne, previewTrackOne, previewClipOne
    case zoomIn, zoomOut, zoomFit, previewZoomValue, previewNavigation
    // Player window
    case playerEmptyTitle, playerEmptyBody, noRenders, colFile, colFolder, colModified
    case setAsPreview, clearPreview, playFile
    case previousSet, nextSet, previousRender, nextRender, volume, mute, unmute
    case waveReading, waveFailed, playerLoading

    var en: String { text.en }
    var ja: String { text.ja }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Home", "ホーム")
        case .previewTitle: return ("Arrangement Preview", "アレンジメントのプレビュー")

        case .readySets: return ("Ready to open", "今すぐ開ける")
        // The bar counts projects (each judged by its newest set): the unit follows the total.
        case .readyProjectsOne: return ("%1$lld / %2$lld project", "%1$lld / %2$lld プロジェクト")
        case .readyProjects: return ("%1$lld / %2$lld projects", "%1$lld / %2$lld プロジェクト")
        case .readySetsHelp: return ("Show the sets that open right now on the Sets tab", "今すぐ開けるセットをセットタブで表示")
        case .overview: return ("Overview", "概要")
        case .activeDays: return ("Active days", "作業した日")
        case .streak: return ("Streak", "連続日数")
        case .noStreak: return ("No streak", "連続記録なし")
        case .record: return ("Record", "最長記録")
        case .peakHour: return ("Peak hour", "ピーク時間帯")
        case .onDisk: return ("%@ on disk", "ディスク使用量 %@")
        case .nothingSaved: return ("nothing saved", "保存なし")
        case .saveOne: return ("%lld save", "%lld 回保存")
        case .saveMany: return ("%lld saves", "%lld 回保存")
        case .daysShort: return ("%lldd", "%lld日")
        case .overviewCollapse: return ("Collapse overview", "概要を閉じる")
        case .overviewExpand: return ("Expand overview", "概要を開く")

        case .dayNotRecorded: return ("Projects were not recorded that day", "この日のプロジェクトは記録されていません")
        case .dayProjectGone: return ("Not in the catalog any more", "カタログにありません")

        case .projects: return ("Projects", "プロジェクト")
        case .shownProjectOne: return ("%lld project shown", "%lld 件のプロジェクトを表示")
        case .shownProjectMany: return ("%lld projects shown", "%lld 件のプロジェクトを表示")
        case .pinnedFirstOn: return ("Pinned projects first (click to sort by date only)",
                                     "ピン留めを先頭に表示中（クリックで日付順のみ）")
        case .pinnedFirstOff: return ("Show pinned projects first", "ピン留めを先頭に表示")
        case .nothingIndexed: return ("nothing indexed yet", "まだインデックスされていません")
        case .noMatches: return ("No projects match the search", "検索に一致するプロジェクトがありません")
        case .newLiveSet: return ("New Live Set", "新しい Live セット")
        case .newLiveSetHelp: return ("Launch Live with a new set", "Live を起動して新しいセットを作成")
        case .noArrangement: return ("no arrangement", "アレンジメントなし")
        case .thumbUnreadable: return ("could not read the set", "セットを読み込めません")
        case .playRender: return ("Play render", "レンダーを再生")
        case .pauseRender: return ("Pause render", "レンダーを一時停止")
        case .openPlayer: return ("Open player", "プレーヤーを開く")
        case .pinProject: return ("Pin project", "プロジェクトをピン留め")
        case .unpin: return ("Unpin", "ピン留めを解除")
        case .showDetails: return ("Show details", "詳細を表示")
        case .pinnedBadge: return ("Pinned", "ピン留め済み")

        case .nowPlayingSeek: return ("Position", "再生位置")
        case .stopPlayback: return ("Stop", "停止")
        case .showSet: return ("Show set", "セットを表示")

        case .previewReading: return ("Reading the set…", "セットを読み込み中…")
        case .previewEmpty: return ("Nothing on the arrangement timeline", "アレンジメントのタイムラインに何もありません")
        case .previewBPM: return ("%@ BPM", "%@ BPM")
        case .previewBars: return ("%lld bars", "%lld 小節")
        case .previewTracks: return ("%lld tracks", "%lld トラック")
        case .previewClips: return ("%lld clips", "%lld クリップ")
        case .previewBarOne: return ("%lld bar", "%lld 小節")
        case .previewTrackOne: return ("%lld track", "%lld トラック")
        case .previewClipOne: return ("%lld clip", "%lld クリップ")
        case .zoomIn: return ("Zoom in", "拡大")
        case .zoomOut: return ("Zoom out", "縮小")
        case .zoomFit: return ("Fit to window", "ウィンドウに合わせる")
        case .previewZoomValue: return ("%@×", "%@×")
        case .previewNavigation:
            return ("Scroll: tracks   ⇧ Scroll: time   ⌘ Scroll or pinch: zoom   ⌥ Scroll: track height   Middle button drag: move",
                    "スクロール: トラック   ⇧ スクロール: 時間   ⌘ スクロール／ピンチ: 拡大縮小   ⌥ スクロール: トラックの高さ   中ボタンドラッグ: 移動")

        case .playerEmptyTitle: return ("Nothing loaded", "何も読み込まれていません")
        case .playerEmptyBody: return ("Press Play on a project tile, or select a set and press the Space bar.",
                                       "プロジェクトタイルの再生ボタンを押すか、セットを選んでスペースキーを押してください。")
        case .noRenders: return ("No renders were found near this project (the Samples folder is skipped).",
                                 "このプロジェクトの近くにレンダーがありません（サンプルフォルダは除外します）。")
        case .colFile: return ("File", "ファイル")
        case .colFolder: return ("Folder", "フォルダ")
        case .colModified: return ("Modified", "更新日")
        case .setAsPreview: return ("Set as Preview", "プレビューに設定")
        case .clearPreview: return ("Clear preview", "プレビューを解除")
        case .playFile: return ("Play", "再生")
        case .previousSet: return ("Previous set", "前のセット")
        case .nextSet: return ("Next set", "次のセット")
        case .previousRender: return ("Previous render", "前のレンダー")
        case .nextRender: return ("Next render", "次のレンダー")
        case .volume: return ("Volume", "音量")
        case .mute: return ("Mute", "ミュート")
        case .unmute: return ("Unmute", "ミュートを解除")
        case .waveReading: return ("reading…", "読み込み中…")
        case .waveFailed: return ("Could not read the waveform", "波形を読み込めません")
        case .playerLoading: return ("Looking for renders…", "レンダーを検索中…")
        }
    }
}

/// "1 project", "2 projects": English needs a sentence of its own for the singular (9ce4b4b).
extension HomeStrings {
    /// The Overview's bar: "24 / 24 projects", "0 / 1 project" (the noun agrees with the total).
    static func readyProjects(ready: Int, total: Int) -> String {
        (total == 1 ? readyProjectsOne : readyProjects).f(ready, total)
    }
    static func projectsShown(_ n: Int) -> String { (n == 1 ? shownProjectOne : shownProjectMany).f(n) }
    static func bars(_ n: Int) -> String { (n == 1 ? previewBarOne : previewBars).f(n) }
    static func tracks(_ n: Int) -> String { (n == 1 ? previewTrackOne : previewTracks).f(n) }
    static func clips(_ n: Int) -> String { (n == 1 ? previewClipOne : previewClips).f(n) }
}
