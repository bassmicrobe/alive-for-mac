// Mac-only: string table for the Stat window (upstream: the literals in nebula/*.cs). en + ja.
import Foundation

enum StatStrings: LocalizedStrings {
    case title
    // Metrics (the values a channel can show)
    case metricTracks, metricPlugins, metricBPM, metricKey, metricScale, metricProjectSize
    case metricSetSize, metricSampleRefs, metricMissingFiles, metricMissingPlugins
    case metricModified, metricCreated, metricLiveVersion, metricCollection, metricName, metricScatter
    // Gradients
    case gradientNebula, gradientOcean
    // Channels and the mapping panel
    case mapping, channelX, channelY, channelZ, channelSize, channelFade, channelColour
    case palette, minFade, maxFade, minSize, maxSize, colourLegend, off, axisTitle
    case channelSwitchHelp
    // Toolbar
    case spin, resetView, presetAngle, presetFront, presetSide, presetTop, presetHelp
    // Cloud
    case projectsCount, hintRotate, hintZoom, hintPan, hintOpen, hintNoFolders, hintNothing, cloudLabel
    // Inspector
    case inspectorEmptyTitle, inspectorEmptyBody, note, files, plugins, noPlugins, showInList

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .title: return ("Statistics", "統計")
        case .metricTracks: return ("Tracks", "トラック")
        case .metricPlugins: return ("Plugins", "プラグイン")
        case .metricBPM: return ("BPM", "BPM")
        case .metricKey: return ("Key", "キー")
        case .metricScale: return ("Scale", "スケール")
        case .metricProjectSize: return ("Project size", "プロジェクトサイズ")
        case .metricSetSize: return ("Set file size", "セットのファイルサイズ")
        case .metricSampleRefs: return ("Sample refs", "サンプル参照数")
        case .metricMissingFiles: return ("Missing files", "見つからないファイル")
        case .metricMissingPlugins: return ("Missing plugins", "見つからないプラグイン")
        case .metricModified: return ("Modified", "更新日")
        case .metricCreated: return ("Created", "作成日")
        case .metricLiveVersion: return ("Live version", "Live バージョン")
        case .metricCollection: return ("Collection", "コレクション")
        case .metricName: return ("Name A→Z", "名前 A→Z")
        case .metricScatter: return ("Scatter (random)", "ばらまき（ランダム）")
        case .gradientNebula: return ("Nebula", "星雲")
        case .gradientOcean: return ("Ocean", "海")
        case .mapping: return ("Mapping", "マッピング")
        case .channelX: return ("X", "X")
        case .channelY: return ("Y", "Y")
        case .channelZ: return ("Z", "Z")
        case .channelSize: return ("Size", "サイズ")
        case .channelFade: return ("Fade", "フェード")
        case .channelColour: return ("Colour", "色")
        case .palette: return ("Palette", "パレット")
        case .minFade: return ("Min fade  ·  %lld%%", "最小フェード  ·  %lld%%")
        case .maxFade: return ("Max fade  ·  %lld%%", "最大フェード  ·  %lld%%")
        case .minSize: return ("Min size  ·  %@ px", "最小サイズ  ·  %@ px")
        case .maxSize: return ("Max size  ·  %@ px", "最大サイズ  ·  %@ px")
        case .colourLegend: return ("Colour  ·  %@", "色  ·  %@")
        case .off: return ("Off", "オフ")
        case .axisTitle: return ("%1$@ · %2$@", "%1$@ · %2$@")
        case .channelSwitchHelp: return ("Show or hide this channel", "このチャンネルの表示を切り替える")
        case .spin: return ("Spin", "回転")
        case .resetView: return ("Reset view", "ビューをリセット")
        case .presetAngle: return ("Free angle", "自由な角度")
        case .presetFront: return ("Front view (X and Y)", "正面（X と Y）")
        case .presetSide: return ("Side view (Z and Y)", "側面（Z と Y）")
        case .presetTop: return ("Top view (X and Z)", "上面（X と Z）")
        case .presetHelp: return ("Camera presets", "カメラのプリセット")
        case .projectsCount: return ("%lld projects", "%lld プロジェクト")
        case .hintRotate: return ("drag — rotate", "ドラッグで回転")
        case .hintZoom: return ("scroll or pinch — zoom", "スクロールかピンチで拡大縮小")
        case .hintPan: return ("right drag — pan", "右ドラッグで移動")
        case .hintOpen: return ("double click — show in Finder", "ダブルクリックで Finder に表示")
        case .hintNoFolders: return ("No folders yet — press the folder button and point at your Ableton projects.",
                                     "フォルダはまだありません。フォルダボタンから Ableton プロジェクトを選んでください。")
        case .hintNothing: return ("Nothing found. Add a folder with .als projects.",
                                   "何も見つかりません。.als プロジェクトのあるフォルダを追加してください。")
        case .cloudLabel: return ("Cloud of %lld projects", "%lld 件のプロジェクトの点群")
        case .inspectorEmptyTitle: return ("No set selected", "セットが選択されていません")
        case .inspectorEmptyBody: return ("Click a dot to see the set here.", "点をクリックすると、ここにセットが表示されます。")
        case .note: return ("Note", "メモ")
        case .files: return ("Files", "ファイル")
        case .plugins: return ("Plugins (%lld)", "プラグイン（%lld）")
        case .noPlugins: return ("No plugins", "プラグインなし")
        case .showInList: return ("Show in list", "リストで表示")
        }
    }
}
