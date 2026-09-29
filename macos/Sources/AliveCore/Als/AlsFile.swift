// Port of src/AlsFile.cs. Mac addition: AuPluginInfo (Audio Units) with FourCC uids.
import Foundation

public enum PluginKind: String, Sendable {
    case vst2 = "Vst2"
    case vst3 = "Vst3"
    case audioUnit = "AudioUnit"
    case maxForLive = "MaxForLive"
}

public struct PluginRef: Equatable, Sendable {
    public var kind: PluginKind
    public var name = ""
    /// "vst3:ed57bd72-…", "vst2:2017543218" or "au:aumf:rmx1:pion" (FourCC text).
    public var uid = ""
    /// From BrowserContentPath, see `AlsFile.parseBrowserPath`; for AU the `Manufacturer` node.
    public var manufacturer = ""
    /// True only for the VST3:Vendor:Name form and for AU's own Manufacturer node.
    public var vendorConfident = false

    var vst3Fields = [Int32](repeating: 0, count: 4)
    var vst3FieldCount = 0
    var vst2UniqueId: Int64?
    var auType: UInt32?, auSubType: UInt32?, auManufacturer: UInt32?

    public init(kind: PluginKind) { self.kind = kind }

    public var key: String { kind.rawValue + "|" + name.lowercased() }

    /// Assembles the uid in the shape Live writes into its plugin database: the four `Fields.*`
    /// are the same 16 bytes of a VST3 class as four ints, most significant byte first. Fields
    /// "-313016974, 1549813374, -1504849164, 7703407" become
    /// "ed57bd72-5c60-467e-a64d-d2f400758b6f" (FabFilter Pro-Q 4).
    mutating func finishUid() {
        switch kind {
        case .vst3 where vst3FieldCount == 4:
            let hex = vst3Fields.map { String(format: "%08x", UInt32(bitPattern: $0)) }.joined()
            let c = Array(hex)
            func part(_ a: Int, _ b: Int) -> String { String(c[a..<b]) }
            uid = "vst3:" + [part(0, 8), part(8, 12), part(12, 16), part(16, 20), part(20, 32)]
                .joined(separator: "-")
        case .vst2:
            if let id = vst2UniqueId { uid = "vst2:\(id)" }
        case .audioUnit:
            if let t = auType, let s = auSubType, let m = auManufacturer {
                uid = "au:" + AlsFile.fourCC(t) + ":" + AlsFile.fourCC(s) + ":" + AlsFile.fourCC(m)
            }
        default: break
        }
    }
}

public struct FileRefInfo: Equatable, Sendable {
    public var relativePath = ""
    public var absolutePath = ""
    public var livePackName = ""
    public var relativePathType = 0
    public var originalFileSize: Int64 = 0
    /// The parent node's name: SampleRef, FilePresetRef, OriginalFileRef and so on.
    public var container = ""

    public init() {}

    /// A set's real dependency is only a clip's sample (parent SampleRef). Everything else
    /// (FilePresetRef, AbletonDefaultPresetRef, OriginalFileRef, Max patches) records where
    /// embedded content came from: Live keeps it inside the set and does not complain about a
    /// missing file on open.
    public var isSampleDependency: Bool { container == "SampleRef" }

    public var pathExtension: String {
        let p = relativePath.isEmpty ? absolutePath : relativePath
        // Sets made on Windows carry backslashes.
        let last = p.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? p
        return (last as NSString).pathExtension.isEmpty ? "" : "." + (last as NSString).pathExtension.lowercased()
    }
}

public struct AlsInfo: Sendable {
    public var path = ""
    /// "Ableton Live 12.3.5"
    public var creator = ""
    public var tempo = 0.0
    /// The set's overall key. -1 means the Live version did not save it.
    public var scaleRoot = -1
    public var scaleIndex = -1
    public var preferFlat = false
    public var audioTracks = 0, midiTracks = 0, groupTracks = 0
    public var plugins: [PluginRef] = []
    public var files: [FileRefInfo] = []
    public var error: String?

    public init() {}

    public var key: String { Scales.format(root: scaleRoot, scaleIndex: scaleIndex, preferFlat: preferFlat) }
    public var totalTracks: Int { audioTracks + midiTracks + groupTracks }
}

/// Reads an .als: gzip over XML (or plain XML). Parsing is streaming (`XMLParser` over the
/// inflated bytes): a typical set is 100 KB on disk and close to 3 MB of XML.
public enum AlsFile {
    /// Never throws: failures land in `AlsInfo.error`, with whatever was parsed before them.
    public static func read(path: String) -> AlsInfo {
        var info = AlsInfo()
        info.path = path
        do {
            let xml = try Gzip.readMaybeGzip(path: path)
            return parse(xml: xml, path: path)
        } catch {
            info.error = error.localizedDescription
            return info
        }
    }

    public static func parse(xml: Data, path: String = "") -> AlsInfo {
        let parser = AlsParser()
        parser.info.path = path
        let stream = ElementStream(onStart: { parser.start($0) }, onEnd: { parser.end($0) })
        parser.info.error = stream.run(xml)
        return parser.info
    }

    /// 32-bit code as four ASCII characters; the decimal number when not printable.
    static func fourCC(_ v: UInt32) -> String {
        let bytes = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(v) }
        return String(bytes: bytes, encoding: .ascii) ?? String(v)
    }

    /// The plugin's developer hides in the browser path Live records next to the device:
    ///     query:Plugins#VST3:FabFilter:Pro-Q%203   -> format, developer, name
    ///     view:X-Plugins#Antares:Auto-Tune%20Pro   -> developer, name
    ///     view:X-Plugins#Decapitator               -> name only
    /// Paths like query:Everything#Reverb belong to Live's built-in devices and are cut off by
    /// the absence of "Plugins#".
    static func parseBrowserPath(_ value: String?) -> (manufacturer: String, confident: Bool)? {
        guard let value, !value.isEmpty,
              value.range(of: "Plugins#", options: .caseInsensitive) != nil,
              let hash = value.firstIndex(of: "#"),
              value.index(after: hash) < value.endIndex else { return nil }

        let parts = value[value.index(after: hash)...].split(separator: ":", omittingEmptySubsequences: false)
        var manufacturer: String?
        var confident = false
        if parts.count >= 3 {
            // query:Plugins#<FORMAT>:<...>:<name>. A genuine vendor sits here only for VST3 and
            // AU; for VST2 ("VST") this slot holds the folder the file lies in ("Gen"/"Eff").
            manufacturer = String(parts[parts.count - 2])
            let format = parts[0].lowercased()
            confident = format == "vst3" || format == "au" || format == "audiounit"
        } else if parts.count == 2 {
            manufacturer = String(parts[0])   // view:X-Plugins#Antares:Auto-Tune Pro
        }
        guard let m = manufacturer, !m.isEmpty else { return nil }
        let clean = (m.removingPercentEncoding ?? m).trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, confident)
    }
}

/// The depth-aware state machine over the element stream (upstream `AlsFile.Parse`).
final class AlsParser {
    var info = AlsInfo()

    private var mainTrackDepth = -1
    private var pluginDepth = -1
    private var plugin: PluginRef?
    private var fileRefDepth = -1
    private var fileRef: FileRefInfo?
    private var fileRefHasChildren = false
    private var tempoSeen = false
    private var tempoDepth = -1
    /// BrowserContentPath comes BEFORE PluginDesc within the same device: remember the last
    /// one seen and hand it to the nearest plugin.
    private var pendingManufacturer: String?
    private var pendingConfident = false
    /// A ScaleInformation node exists on every clip too — the one we want is directly in LiveSet.
    private var songScaleDepth = -1

    func end(_ depth: Int) {
        if pluginDepth >= 0 && depth <= pluginDepth {
            if var p = plugin, !p.name.isEmpty {
                p.finishUid()
                info.plugins.append(p)
            }
            plugin = nil; pluginDepth = -1
        }
        if fileRefDepth >= 0 && depth <= fileRefDepth {
            if let f = fileRef, fileRefHasChildren { info.files.append(f) }
            fileRef = nil; fileRefDepth = -1
        }
        if mainTrackDepth >= 0 && depth <= mainTrackDepth { mainTrackDepth = -1 }
        if tempoDepth >= 0 && depth <= tempoDepth { tempoDepth = -1 }
        if songScaleDepth >= 0 && depth <= songScaleDepth { songScaleDepth = -1 }
    }

    func start(_ e: XMLTag) {
        openContext(e)
        if plugin != nil { pluginChild(e) }
        if fileRef != nil, e.depth == fileRefDepth + 1 { fileRefChild(e) }
        if tempoDepth >= 0, e.name == "Manual", e.depth == tempoDepth + 1 {
            let t = e.double(0)
            if t > 0 { info.tempo = t; tempoSeen = true }
        }
        if songScaleDepth >= 0, e.depth == songScaleDepth + 1 {
            if e.name == "Root" { info.scaleRoot = e.int() } else if e.name == "Name" { info.scaleIndex = e.int() }
        }
    }

    private func openContext(_ e: XMLTag) {
        switch e.name {
        case "Ableton": info.creator = e.attrs["Creator"] ?? ""
        case "AudioTrack": info.audioTracks += 1
        case "MidiTrack": info.midiTracks += 1
        case "GroupTrack": info.groupTracks += 1
        case "MainTrack", "MasterTrack": mainTrackDepth = e.depth     // "Master" before Live 12
        case "BrowserContentPath":
            if let m = AlsFile.parseBrowserPath(e.value) {
                pendingManufacturer = m.manufacturer; pendingConfident = m.confident
            }
        case "Vst3PluginInfo": openPlugin(.vst3, e)
        case "VstPluginInfo": openPlugin(.vst2, e)
        case "AuPluginInfo": openPlugin(.audioUnit, e)
        case "FileRef":
            var f = FileRefInfo()
            f.container = e.parent   // SampleRef = a real sample, the rest is provenance
            fileRef = f; fileRefDepth = e.depth; fileRefHasChildren = false
        case "Tempo":
            if mainTrackDepth >= 0 && !tempoSeen { tempoDepth = e.depth }
        case "ScaleInformation":
            if e.parent == "LiveSet" { songScaleDepth = e.depth }
        case "PreferFlatRootNote":
            if e.parent == "LiveSet" { info.preferFlat = e.bool }
        default: break
        }
    }

    private func openPlugin(_ kind: PluginKind, _ e: XMLTag) {
        var p = PluginRef(kind: kind)
        if let m = pendingManufacturer {
            p.manufacturer = m
            p.vendorConfident = pendingConfident
            pendingManufacturer = nil     // one path per plugin
            pendingConfident = false
        }
        plugin = p; pluginDepth = e.depth
    }

    /// Values inside the plugin node. Only direct children (depth + 1) count: an empty
    /// `<Name Value=""/>` sits nested in the preset block of a Vst3PluginInfo, and AU carries a
    /// `<Preset>` too — without the depth guard the real names would be lost.
    private func pluginChild(_ e: XMLTag) {
        guard var p = plugin else { return }
        defer { plugin = p }
        if e.depth == pluginDepth + 1 {
            switch e.name {
            case "PlugName", "Name": if let v = e.value, !v.isEmpty { p.name = v }
            case "UniqueId": p.vst2UniqueId = e.int64()
            case "Manufacturer":
                // On an Audio Unit the vendor is written right in the node — a reliable source.
                if let v = e.value, !v.isEmpty { p.manufacturer = v; p.vendorConfident = true }
            case "ComponentType": p.auType = UInt32(truncatingIfNeeded: e.int64())
            case "ComponentSubType": p.auSubType = UInt32(truncatingIfNeeded: e.int64())
            case "ComponentManufacturer": p.auManufacturer = UInt32(truncatingIfNeeded: e.int64())
            default: break
            }
        }
        // <Vst3PluginInfo><Uid><Fields.0../></Uid> — only these four.
        if e.parent == "Uid", e.depth == pluginDepth + 2, e.name.hasPrefix("Fields."),
           p.vst3FieldCount < 4, let slot = Int(e.name.dropFirst(7)), (0..<4).contains(slot) {
            p.vst3Fields[slot] = Int32(truncatingIfNeeded: e.int64())
            p.vst3FieldCount += 1
        }
    }

    private func fileRefChild(_ e: XMLTag) {
        guard var f = fileRef else { return }
        fileRefHasChildren = true
        switch e.name {
        case "RelativePath": f.relativePath = e.value ?? ""
        case "Path": f.absolutePath = e.value ?? ""
        case "LivePackName": f.livePackName = e.value ?? ""
        case "RelativePathType": f.relativePathType = e.int()
        case "OriginalFileSize": f.originalFileSize = e.int64()
        default: break
        }
        fileRef = f
    }
}
