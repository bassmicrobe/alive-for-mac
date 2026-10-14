// Mac-only: the HTML page the Quick Look extension shows for an .als. Everything here is pure
// (a parsed set in, a string out) so it is unit-tested without Finder; only `PreviewModel.load`
// touches the disk. Foundation, CoreGraphics and ImageIO only: extension-safe.
import AliveCore
import CoreGraphics
import Foundation
import ImageIO

/// What the page shows about one set.
public struct PreviewModel: Sendable {
    public var path: String
    public var fileSize: Int64
    public var modified: Date?
    public var info: AlsInfo
    public var arrangement: Arrangement

    public init(path: String, fileSize: Int64 = 0, modified: Date? = nil, info: AlsInfo, arrangement: Arrangement) {
        self.path = path; self.fileSize = fileSize; self.modified = modified
        self.info = info; self.arrangement = arrangement
    }

    public var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// Reads the file once and parses it twice (details, arrangement). Never throws: a failure
    /// lands in `info.error`.
    public static func load(path: String) -> PreviewModel {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attrs?[.modificationDate] as? Date
        do {
            let xml = try Gzip.readMaybeGzip(path: path)
            return PreviewModel(path: path, fileSize: size, modified: modified,
                                info: AlsFile.parse(xml: xml, path: path),
                                arrangement: Arrangement.parse(xml: xml, path: path))
        } catch {
            var info = AlsInfo()
            info.path = path
            info.error = error.localizedDescription
            var arrangement = Arrangement()
            arrangement.path = path
            arrangement.error = info.error
            return PreviewModel(path: path, fileSize: size, modified: modified, info: info, arrangement: arrangement)
        }
    }
}

public enum PreviewPage {
    /// The id the picture is attached under (`cid:` URL).
    public static let pictureID = "arrangement.png"
    /// Longest plug-in list shown; the rest is summarised.
    public static let maxPlugins = 36
    /// The page's natural size (points), for `QLPreviewReply.contentSize`.
    public static let contentSize = CGSize(width: 760, height: 720)

    // MARK: picture

    /// The arrangement as PNG data, or nil when the set has nothing to draw.
    public static func pictureData(for a: Arrangement, width: Int = 1500) -> Data? {
        guard a.hasContent, !a.tracks.isEmpty else { return nil }
        let options = RenderOptions(showNames: true, showRuler: true, showClipNames: false,
                                    minLane: 6, maxLane: 26, scale: 2)
        let natural = ArrangementRender.fullHeight(trackCount: a.tracks.count, options: options)
        let height = min(max(natural, 300), 1100)
        guard let image = ArrangementRender.makeImage(a, width: width, height: height, options: options) else { return nil }
        return png(image)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: html

    /// `pictureSource` is the `src` of the arrangement image (`cid:arrangement.png` or a data
    /// URL); nil leaves the picture out.
    public static func html(_ m: PreviewModel, language: PreviewLanguage, pictureSource: String?) -> String {
        func t(_ s: PreviewString) -> String { s.text(language) }
        let info = m.info, a = m.arrangement

        let tempoValue = info.tempo > 0 ? number(info.tempo) : (a.tempo > 0 ? number(a.tempo) : "")
        let tempo = tempoValue.isEmpty ? t(.none) : "\(tempoValue) <small>\(t(.bpm))</small>"
        let key = info.key.isEmpty ? t(.unknownKey) : escape(info.key)
        let trackBreakdown = trackLine(info, language)

        var stats = tile(t(.tempo), tempo)
        stats += tile(t(.key), key)
        stats += tile(t(.tracks), "\(info.totalTracks)", note: trackBreakdown)
        stats += tile(t(.length), lengthText(a, tempo: info.tempo > 0 ? info.tempo : a.tempo, language))

        let version = escape(info.creator)
        let subtitle = [version, savedText(m, language)].filter { !$0.isEmpty }.joined(separator: " &middot; ")

        var body = "<header><h1>\(escape(m.name))</h1><p class=\"sub\">\(subtitle)</p></header>"
        body += "<section class=\"stats\">\(stats)</section>"
        if let error = info.error, info.totalTracks == 0 {
            body += "<p class=\"warn\">\(t(.readFailed)) <span>\(escape(error))</span></p>"
        }
        body += pictureSection(a, source: pictureSource, language)
        body += pluginSection(info, language)
        body += filesSection(info, language)
        body += "<footer><span>\(t(.location))</span> <code>\(escape(m.path))</code></footer>"

        return "<!doctype html><html lang=\"\(language == .ja ? "ja" : "en")\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width\"><style>\(css)</style></head><body>\(body)</body></html>"
    }

    // MARK: sections

    private static func tile(_ label: String, _ value: String, note: String = "") -> String {
        let extra = note.isEmpty ? "" : "<em>\(note)</em>"
        return "<div class=\"tile\"><span>\(label)</span><strong>\(value)</strong>\(extra)</div>"
    }

    private static func trackLine(_ info: AlsInfo, _ language: PreviewLanguage) -> String {
        var parts: [String] = []
        if info.audioTracks > 0 { parts.append("\(info.audioTracks) \(PreviewString.audio.text(language))") }
        if info.midiTracks > 0 { parts.append("\(info.midiTracks) \(PreviewString.midi.text(language))") }
        if info.groupTracks > 0 { parts.append("\(info.groupTracks) \(PreviewString.group.text(language))") }
        return parts.joined(separator: " · ")
    }

    private static func pictureSection(_ a: Arrangement, source: String?, _ language: PreviewLanguage) -> String {
        let title = PreviewString.arrangement.text(language)
        if let source, a.hasContent {
            return "<section class=\"card\"><h2>\(title)</h2><img alt=\"\(title)\" src=\"\(escape(source))\"></section>"
        }
        let note = a.error == nil ? PreviewString.emptyArrangement.text(language) : ""
        return note.isEmpty ? "" : "<section class=\"card\"><h2>\(title)</h2><p class=\"dim\">\(note)</p></section>"
    }

    /// Distinct plug-ins, by name; no judgement about installed or missing (the sandbox cannot see them).
    static func pluginRows(_ info: AlsInfo) -> [PluginRef] {
        var seen = Set<String>()
        let unique = info.plugins.filter { !$0.name.isEmpty && seen.insert($0.key).inserted }
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func pluginSection(_ info: AlsInfo, _ language: PreviewLanguage) -> String {
        let title = PreviewString.plugins.text(language)
        let rows = pluginRows(info)
        guard !rows.isEmpty else {
            return "<section class=\"card\"><h2>\(title)</h2><p class=\"dim\">\(PreviewString.noPlugins.text(language))</p></section>"
        }
        var chips = rows.prefix(maxPlugins).map { p -> String in
            let vendor = p.manufacturer.isEmpty ? "" : "<i>\(escape(p.manufacturer))</i>"
            return "<li><b>\(kindLabel(p.kind))</b>\(escape(p.name))\(vendor)</li>"
        }.joined()
        if rows.count > maxPlugins {
            chips += "<li class=\"more\">+\(rows.count - maxPlugins) \(PreviewString.moreSuffix.text(language))</li>"
        }
        return "<section class=\"card\"><h2>\(title) <small>\(rows.count)</small></h2><ul class=\"chips\">\(chips)</ul></section>"
    }

    private static func kindLabel(_ kind: PluginKind) -> String {
        switch kind {
        case .vst2: return "VST2"
        case .vst3: return "VST3"
        case .audioUnit: return "AU"
        case .maxForLive: return "M4L"
        }
    }

    /// Counts of distinct samples and other referenced files.
    static func fileCounts(_ info: AlsInfo) -> (samples: Int, others: Int) {
        var samples = Set<String>(), others = Set<String>()
        for f in info.files {
            let key = f.absolutePath.isEmpty ? f.relativePath : f.absolutePath
            guard !key.isEmpty else { continue }
            if f.isSampleDependency { samples.insert(key) } else { others.insert(key) }
        }
        return (samples.count, others.count)
    }

    private static func filesSection(_ info: AlsInfo, _ language: PreviewLanguage) -> String {
        let (samples, others) = fileCounts(info)
        if samples == 0 && others == 0 {
            return "<section class=\"files\"><span class=\"dim\">\(PreviewString.noFiles.text(language))</span></section>"
        }
        return "<section class=\"files\"><div><span>\(PreviewString.samples.text(language))</span> <strong>\(samples)</strong></div>"
            + "<div><span>\(PreviewString.otherFiles.text(language))</span> <strong>\(others)</strong></div></section>"
    }

    // MARK: formatting

    static func number(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        let text = String(format: "%.2f", rounded)
        return text.hasSuffix("0") ? String(text.dropLast()) : text
    }

    /// "3:42 · 120 bars", or "—" for an empty arrangement.
    static func lengthText(_ a: Arrangement, tempo: Double, _ language: PreviewLanguage) -> String {
        guard a.end > 0, tempo > 0 else { return PreviewString.none.text(language) }
        let seconds = Int((a.end * 60 / tempo).rounded())
        let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return "\(clock) <small>\(a.bars) \(PreviewString.bars.text(language))</small>"
    }

    private static func savedText(_ m: PreviewModel, _ language: PreviewLanguage) -> String {
        var parts: [String] = []
        if let modified = m.modified {
            let f = DateFormatter()
            f.locale = language.locale
            f.dateStyle = .medium
            f.timeStyle = .short
            parts.append(escape(f.string(from: modified)))
        }
        if m.fileSize > 0 {
            parts.append(escape(ByteSize.string(m.fileSize, locale: language.locale)))
        }
        return parts.joined(separator: " &middot; ")
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: style (the app's palette: Theme.swift)

    static let css = """
    :root{color-scheme:dark}
    *{box-sizing:border-box}
    body{margin:0;padding:26px 28px 22px;background:#1B1B1D;color:#E9E9EB;
      font:13px/1.45 -apple-system,BlinkMacSystemFont,"Hiragino Sans",sans-serif;-webkit-font-smoothing:antialiased}
    header{margin-bottom:18px}
    h1{margin:0;font-size:26px;font-weight:650;letter-spacing:-.01em;overflow-wrap:anywhere}
    .sub{margin:4px 0 0;color:#AEAEB3}
    .stats{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:14px}
    .tile{background:#28282A;border:1px solid rgba(255,255,255,.05);border-radius:14px;padding:11px 14px 12px;
      box-shadow:inset 0 1px 0 rgba(255,255,255,.08)}
    .tile span{display:block;color:#919196;font-size:11px;text-transform:uppercase;letter-spacing:.06em}
    .tile strong{display:block;margin-top:2px;font-size:21px;font-weight:600;font-variant-numeric:tabular-nums}
    .tile small{font-size:11px;font-weight:500;color:#AEAEB3}
    .tile em{display:block;margin-top:1px;font-style:normal;font-size:11px;color:#919196}
    .card{background:#28282A;border:1px solid rgba(255,255,255,.05);border-radius:14px;padding:14px 16px 16px;margin-bottom:12px}
    h2{margin:0 0 10px;font-size:12px;font-weight:600;color:#919196;text-transform:uppercase;letter-spacing:.06em}
    h2 small{margin-left:6px;color:#CACACB;font-size:12px}
    img{display:block;width:100%;height:auto;border-radius:8px;background:#151519}
    .chips{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:6px}
    .chips li{background:rgba(255,255,255,.07);border-radius:999px;padding:3px 11px 3px 4px;color:#E9E9EB;display:flex;gap:7px;align-items:center}
    .chips li b{background:#3A3A3E;color:#CACACB;font-size:9.5px;font-weight:600;border-radius:999px;padding:2px 7px}
    .chips li i{font-style:normal;color:#919196}
    .chips li.more{padding:3px 11px;color:#919196}
    .files{display:flex;gap:26px;margin:4px 4px 14px;color:#AEAEB3}
    .files strong{color:#E9E9EB;font-variant-numeric:tabular-nums}
    .dim{color:#919196;margin:0}
    .warn{background:rgba(225,97,97,.14);color:#FF8585;border-radius:10px;padding:8px 12px}
    .warn span{color:#919196}
    footer{margin-top:6px;padding-top:12px;border-top:1px solid #3A3A3D;color:#919196;font-size:11.5px}
    footer code{display:block;margin-top:2px;font:11.5px ui-monospace,Menlo,monospace;color:#AEAEB3;overflow-wrap:anywhere}
    """
}
