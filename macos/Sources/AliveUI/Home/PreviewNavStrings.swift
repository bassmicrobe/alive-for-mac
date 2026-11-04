// Mac-only: the words the full-screen preview added in upstream 1.3.x — the singular caption forms
// ("1 bar", 9ce4b4b) and the navigation hint. A table of its own because HomeStrings belongs to
// the Home work; fold it into HomeStrings when convenient.
import Foundation

enum PreviewNavStrings: LocalizedStrings {
    case bar1, track1, clip1
    case zoomValue, navigationHelp

    var en: String { text.en }
    var ja: String { text.ja }

    private var text: (en: String, ja: String) {
        switch self {
        case .bar1: return ("%lld bar", "%lld 小節")
        case .track1: return ("%lld track", "%lld トラック")
        case .clip1: return ("%lld clip", "%lld クリップ")
        case .zoomValue: return ("%@×", "%@×")
        case .navigationHelp:
            return ("Scroll: tracks   ⇧ Scroll: time   ⌘ Scroll or pinch: zoom   ⌥ Scroll: track height   Middle button drag: move",
                    "スクロール: トラック   ⇧ スクロール: 時間   ⌘ スクロール／ピンチ: 拡大縮小   ⌥ スクロール: トラックの高さ   中ボタンドラッグ: 移動")
        }
    }
}
