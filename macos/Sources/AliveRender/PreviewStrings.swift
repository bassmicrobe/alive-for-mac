// Mac-only: the words of the Quick Look page. A small table of its own (not the app's Localizer):
// the extension runs in another process and chooses English or Japanese from the system locale.
import Foundation

public enum PreviewLanguage: Sendable {
    case en, ja

    /// Japanese when the first preferred language is Japanese, English otherwise.
    public static func system(preferred: [String] = Locale.preferredLanguages) -> PreviewLanguage {
        preferred.first.map { $0.lowercased().hasPrefix("ja") } == true ? .ja : .en
    }

    var locale: Locale { Locale(identifier: self == .ja ? "ja_JP" : "en_US") }
}

public enum PreviewString: CaseIterable, Sendable {
    case tempo, key, tracks, length, bars, arrangement, plugins, noPlugins, moreSuffix
    case samples, otherFiles, noFiles, location, saved, size, readFailed, emptyArrangement
    case audio, midi, group, none, bpm, unknownKey

    public func text(_ language: PreviewLanguage) -> String {
        let pair = table
        return language == .ja ? pair.ja : pair.en
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private var table: (en: String, ja: String) {
        switch self {
        case .tempo: return ("Tempo", "テンポ")
        case .key: return ("Key", "キー")
        case .tracks: return ("Tracks", "トラック")
        case .length: return ("Length", "長さ")
        case .bars: return ("bars", "小節")
        case .arrangement: return ("Arrangement", "アレンジメント")
        case .plugins: return ("Plug-ins", "プラグイン")
        case .noPlugins: return ("No third-party plug-ins", "サードパーティ製プラグインなし")
        case .moreSuffix: return ("more", "件")
        case .samples: return ("Samples", "サンプル")
        case .otherFiles: return ("Other files", "その他のファイル")
        case .noFiles: return ("No external files", "外部ファイルなし")
        case .location: return ("Location", "場所")
        case .saved: return ("Saved", "保存日時")
        case .size: return ("Size", "サイズ")
        case .readFailed: return ("This set could not be read completely.", "このセットを完全には読み込めませんでした。")
        case .emptyArrangement: return ("Nothing on the arrangement timeline.", "アレンジメントに何も置かれていません。")
        case .audio: return ("audio", "オーディオ")
        case .midi: return ("MIDI", "MIDI")
        case .group: return ("group", "グループ")
        case .none: return ("—", "—")
        case .bpm: return ("BPM", "BPM")
        case .unknownKey: return ("—", "—")
        }
    }
}
