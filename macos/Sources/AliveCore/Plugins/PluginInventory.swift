// Port of src/PluginInventory.cs. On macOS the list is assembled from the plugin bundles on disk
// (see PluginBundleScanner) and, when Live keeps one, from its own plugin database and scanner
// log (see PluginScanDb); the loading itself is in PluginInventory+Load.swift.
import Foundation

public struct InstalledPlugin: Equatable, Hashable, Sendable {
    /// "vst3:ed57bd72-…" / "vst2:2017543218" / "au:aumf:rmx1:pion". A bundle whose identifier
    /// cannot be read without loading its code gets "file:<format>:<name>" and is identified by
    /// name instead (see `PluginInventory.match`).
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
    /// Other spellings a set may use for this plugin (the bundle's file name, for one): indexed
    /// by name next to `name` and `vendor + name`.
    public var aliases: [String] = []

    public init() {}

    public var format: String {
        switch kind {
        case .vst3: return "VST3"
        case .vst2: return "VST2"
        default: return "AU"
        }
    }

    /// The uid prefix `AlsFile` uses for this format.
    static func uidPrefix(of kind: PluginKind) -> String {
        switch kind {
        case .vst3: return "vst3"
        case .vst2: return "vst2"
        default: return "au"
        }
    }

    /// The uid of a plugin found by its file alone.
    static func fileUid(kind: PluginKind, name: String) -> String {
        "file:" + uidPrefix(of: kind) + ":" + PluginInventory.normalize(name)
    }

    /// True when only the file, not the plugin's own identifier, is known.
    var isFileIdentified: Bool { uid.hasPrefix("file:") }
}

public enum MatchKind: Sendable {
    /// The very same plugin: the identifier matched.
    case exact
    /// Such a plugin exists but in another format — the set will still open, with a hole.
    case otherFormat
    /// Nothing resembling it is installed.
    case missing
    /// Cannot tell: the list of installed plugins is not available (see
    /// `PluginInventory.isAvailable`). Never shown as a problem.
    case unknown
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
    private var byNameMap: [String: [InstalledPlugin]] = [:]   // normalized name -> candidates

    public init() {}

    public var isEmpty: Bool { all.isEmpty }

    /// Whether the list of installed plugins can be trusted. An empty list means the machine's
    /// plugins could not be read (Live keeps no database here and no plugin folder held anything),
    /// not that none are installed: nothing is reported as "missing" from it, the status of every
    /// plugin is `MatchKind.unknown`.
    public var isAvailable: Bool { !all.isEmpty }

    public mutating func add(_ p: InstalledPlugin) {
        all.append(p)
        index(p)
    }

    /// Adds many at once, keeping one plugin per identifier (the first wins, unless it is a
    /// stale record and a later one has its file on disk) — upstream `Reindex`. One plugin gets
    /// in several times when Live sees several of its files, or when a folder is listed twice.
    public mutating func add(contentsOf list: [InstalledPlugin]) {
        var slot: [String: Int] = [:]
        var merged = all
        for (i, p) in all.enumerated() where !p.uid.isEmpty { slot[p.uid.lowercased()] = i }
        for p in list {
            let key = p.uid.lowercased()
            if key.isEmpty { merged.append(p); continue }
            guard let at = slot[key] else { slot[key] = merged.count; merged.append(p); continue }
            if merged[at].fileMissing && !p.fileMissing { merged[at] = p }
        }
        all = merged
        byUidMap = [:]
        byNameMap = [:]
        for p in all { index(p) }
    }

    private mutating func index(_ p: InstalledPlugin) {
        if !p.uid.isEmpty, byUidMap[p.uid.lowercased()] == nil { byUidMap[p.uid.lowercased()] = p }
        for key in [p.name, p.vendor + p.name] + p.aliases {
            let n = Self.normalize(key)
            if n.count > 1 { byNameMap[n, default: []].append(p) }
        }
    }

    public func byUid(_ uid: String) -> InstalledPlugin? {
        uid.isEmpty ? nil : byUidMap[uid.lowercased()]
    }

    /// A fallback: a set may have been saved with the VST2 version of a plugin while the VST3 one
    /// is now installed — different identifiers, essentially the same plugin. It also catches the
    /// case where the set has the name with the vendor ("FabFilter Pro-L 2") while the bundle is
    /// known in short ("Pro-L 2" by FabFilter).
    public func byName(_ name: String) -> InstalledPlugin? {
        candidates(named: name).first
    }

    func candidates(named name: String) -> [InstalledPlugin] {
        name.isEmpty ? [] : byNameMap[Self.normalize(name)] ?? []
    }

    /// How confidently a plugin from a set was identified among the installed ones.
    ///
    /// Mac addition: a bundle whose own identifier we cannot read (most VST3 and VST2 bundles
    /// have no moduleinfo.json, and reading the class id would mean loading the plugin) is
    /// identified by name. If it has the same name *and* the same format as the plugin in the set
    /// it counts as the same plugin, not as "other format".
    public func match(uid: String, name: String) -> PluginMatch {
        if !isAvailable { return PluginMatch(plugin: nil, kind: .unknown) }
        if let p = byUid(uid) { return PluginMatch(plugin: p, kind: .exact) }
        let found = candidates(named: name)
        if let same = found.first(where: { $0.isFileIdentified && Self.sameFormat($0, uid: uid) }) {
            return PluginMatch(plugin: same, kind: .exact)
        }
        if let p = found.first { return PluginMatch(plugin: p, kind: .otherFormat) }
        return PluginMatch(plugin: nil, kind: .missing)
    }

    private static func sameFormat(_ p: InstalledPlugin, uid: String) -> Bool {
        uid.hasPrefix(InstalledPlugin.uidPrefix(of: p.kind) + ":")
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

    /// English one-liner for logs/diagnostics (the UI localizes its own text).
    public func describe() -> String {
        if let error { return error }
        var parts = ["\(all.count) plugins"]
        if !liveVersion.isEmpty { parts.append(liveVersion) }
        if scanned != .distantPast {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            parts.append(f.string(from: scanned))
        }
        return parts.joined(separator: " · ")
    }
}
