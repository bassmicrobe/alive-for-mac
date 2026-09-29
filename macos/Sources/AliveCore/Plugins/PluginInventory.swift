// Port of src/PluginInventory.cs — MINIMAL STUB. The real macOS inventory (Audio Unit / VST /
// VST3 bundles, moduleinfo.json, Live's PluginScanDb.txt when present) is implemented by
// implementer S3 behind this same API; keep the signatures.
import Foundation

public struct InstalledPlugin: Equatable, Hashable, Sendable {
    /// "vst3:ed57bd72-…" / "vst2:2017543218" / "au:aumf:rmx1:pion"
    public var uid = ""
    public var name = ""
    public var vendor = ""
    public var version = ""
    public var category = ""
    /// The .vst3 / .vst / .component bundle.
    public var path = ""
    public var kind: PluginKind = .vst3
    public var enabled = true
    /// Live knows it, but the file is no longer on disk.
    public var fileMissing = false

    public init() {}

    public var format: String {
        switch kind {
        case .vst3: return "VST3"
        case .vst2: return "VST2"
        default: return "AU"
        }
    }
}

public enum MatchKind: Sendable {
    /// The very same plugin: the identifier matched.
    case exact
    /// Such a plugin exists but in another format — the set will still open, with a hole.
    case otherFormat
    /// Nothing resembling it is installed.
    case missing
}

public struct PluginMatch: Sendable {
    public let plugin: InstalledPlugin?
    public let kind: MatchKind
    public init(plugin: InstalledPlugin?, kind: MatchKind) { self.plugin = plugin; self.kind = kind }
    public var found: Bool { kind != .missing }
}

/// Which plugins are installed on this machine. Identification is by identifier, not by name.
public struct PluginInventory: Sendable {
    public private(set) var all: [InstalledPlugin] = []
    /// Which sources the list was assembled from — for the settings window.
    public var sources: [String] = []
    public var sourcePath = ""
    public var liveVersion = ""
    public var scanned = Date.distantPast
    public var error: String?

    private var byUidMap: [String: InstalledPlugin] = [:]      // lowercased uid
    private var byNameMap: [String: InstalledPlugin] = [:]     // normalized name

    public init() {}

    public var isEmpty: Bool { all.isEmpty }

    public mutating func add(_ p: InstalledPlugin) {
        all.append(p)
        if !p.uid.isEmpty, byUidMap[p.uid.lowercased()] == nil { byUidMap[p.uid.lowercased()] = p }
        let n = Self.normalize(p.name)
        if !n.isEmpty, byNameMap[n] == nil { byNameMap[n] = p }
    }

    public func byUid(_ uid: String) -> InstalledPlugin? {
        uid.isEmpty ? nil : byUidMap[uid.lowercased()]
    }

    /// A fallback: a set may have been saved with the VST2 version of a plugin while the VST3 one
    /// is now installed — different identifiers, essentially the same plugin.
    public func byName(_ name: String) -> InstalledPlugin? {
        name.isEmpty ? nil : byNameMap[Self.normalize(name)]
    }

    /// How confidently a plugin from a set was identified among the installed ones.
    public func match(uid: String, name: String) -> PluginMatch {
        if let p = byUid(uid) { return PluginMatch(plugin: p, kind: .exact) }
        if let p = byName(name) { return PluginMatch(plugin: p, kind: .otherFormat) }
        return PluginMatch(plugin: nil, kind: .missing)
    }

    /// Names like "Serum_x64" and "Serum (64 Bit)" are one and the same plugin.
    public static func normalize(_ name: String) -> String {
        var s = String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }).lowercased()
        for tail in ["x64", "64bit", "64", "x86", "win", "vst3", "vst"]
        where s.count > tail.count + 2 && s.hasSuffix(tail) {
            s.removeLast(tail.count)
        }
        return s
    }

    /// STUB: returns an empty inventory. S3 replaces this with the real macOS scan.
    public static func load(settings: Settings) -> PluginInventory {
        PluginInventory()
    }

    /// English one-liner for logs/diagnostics (the UI localizes its own text).
    public func describe() -> String {
        if let error { return error }
        return "\(all.count) plugins" + (liveVersion.isEmpty ? "" : " · " + liveVersion)
    }
}
