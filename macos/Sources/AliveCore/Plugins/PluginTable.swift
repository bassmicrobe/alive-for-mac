// Port of the plugin table logic in src/MainForm.cs (PluginCatalog columns, PluginStatusRank,
// CompareVersion, PassesView, FillPlugins' search) and of src/DetailPanel.cs ShowPlugin (the sets
// a plugin is used in). Mac additions: "last used" and the instrument/effect role.
import Foundation

/// The state a row shows: a green mark, "other format", or a red cross (not installed, or Live
/// remembers it but the file is gone).
public enum PluginStatus: Int, Comparable, Sendable {
    case installed = 0, otherFormat = 1, missing = 2
    /// Not known: the list of installed plugins is unavailable.
    case unknown = 3

    public static func < (a: PluginStatus, b: PluginStatus) -> Bool { a.rawValue < b.rawValue }
}

public enum PluginRole: Sendable {
    case instrument, effect, unknown
}

extension PluginStat {
    /// upstream `PluginStatusRank`.
    public var status: PluginStatus {
        if match == .unknown { return .unknown }
        if match == .missing || (installed?.fileMissing ?? false) { return .missing }
        return match == .otherFormat ? .otherFormat : .installed
    }

    /// Instrument or effect, from the category of the installed plugin ("Instrument|Synth",
    /// "Fx|EQ", an Audio Unit's type). Unknown when the plugin is not installed or the bundle
    /// carries no category.
    public var role: PluginRole {
        guard let cat = installed?.category.trimmingCharacters(in: .whitespaces), !cat.isEmpty else { return .unknown }
        let parts = cat.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if parts.first == "fx" || parts.first == "midi effect" { return .effect }
        let instrumental = ["instrument", "synth", "generator", "sampler", "drum"]
        return parts.contains { p in instrumental.contains { p.contains($0) } } ? .instrument : .effect
    }
}

/// One line of the plugins table.
public struct PluginRow: Identifiable, Sendable {
    public let stat: PluginStat
    /// The newest modification time among the sets that use it; nil when unused.
    public let lastUsed: Date?

    public var id: String { stat.uid + "|" + stat.name.lowercased() }
    public var name: String { stat.name }
    public var vendor: String { stat.vendor }
    public var fxType: String { stat.fxType }
    public var format: String { stat.format }
    public var sets: Int { stat.sets }
    public var status: PluginStatus { stat.status }
    public var role: PluginRole { stat.role }
    public var version: String { stat.installed?.version ?? "" }
    public var path: String { stat.installed?.path ?? "" }

    public init(stat: PluginStat, lastUsed: Date?) {
        self.stat = stat
        self.lastUsed = lastUsed
    }

    /// Search over name, vendor, type and format, all words must hit (upstream: the whole text as
    /// one substring; words are friendlier for "fabfilter eq").
    public func matches(search words: [String]) -> Bool {
        if words.isEmpty { return true }
        let hay = [name, vendor, fxType, format].joined(separator: "\n")
        return words.allSatisfy { hay.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// The plugins of a catalog with what the table and the inspector need, built once per snapshot.
public struct PluginTable: Sendable {
    public let rows: [PluginRow]
    private let setsByName: [String: [SetEntry]]

    public init(usage: [PluginStat], sets: [SetEntry]) {
        var by: [String: [SetEntry]] = [:]
        for s in sets {
            var seen = Set<String>()
            for n in s.plugins where seen.insert(n.lowercased()).inserted { by[n.lowercased(), default: []].append(s) }
        }
        setsByName = by
        rows = usage.map { st in
            PluginRow(stat: st, lastUsed: by[st.name.lowercased()]?.map(\.modified).max())
        }
    }

    /// The sets a plugin is used in, newest first (upstream lists them in catalog order; newest
    /// first is what one wants to open).
    public func sets(using name: String) -> [SetEntry] {
        (setsByName[name.lowercased()] ?? []).sorted { $0.modified > $1.modified }
    }

    /// The row a set's plugin list points at: the used one if there is one.
    public func row(named name: String) -> PluginRow? {
        rows.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: - The summary cards

/// The four cards above the list. A card is also a filter: "not installed" leaves exactly the
/// plugins the card talks about.
public enum PluginCard: Int, CaseIterable, Identifiable, Sendable {
    case used, installed, missing, unused

    public var id: Int { rawValue }

    public enum Tone: Sendable { case normal, good, bad, dim }

    public func value(_ h: PluginHealth) -> Int {
        switch self {
        case .used: return h.used
        case .installed: return h.installedTotal
        case .missing: return h.missing
        case .unused: return h.installedUnused
        }
    }

    public func tone(_ h: PluginHealth) -> Tone {
        switch self {
        case .used: return .normal
        case .installed: return .good
        case .missing: return value(h) > 0 ? .bad : .normal
        case .unused: return .dim
        }
    }

    /// upstream `PassesView`.
    public func passes(_ st: PluginStat) -> Bool {
        switch self {
        case .used: return st.sets > 0
        case .missing: return st.sets > 0 && st.match == .missing
        case .installed: return st.isInstalled
        case .unused: return st.sets == 0
        }
    }
}

// MARK: - Sorting

public enum PluginColumn: String, CaseIterable, Sendable {
    case name, vendor, fxType, format, sets, lastUsed, version, file, status
}

/// Sorts rows like upstream's column comparers. Rows with nothing in the column (no developer, no
/// version, never used) go last in either direction: the column is there to find things by
/// author, not to admire the emptiness at the top of the list.
public struct PluginSort: SortComparator, Hashable, Sendable {
    public var column: PluginColumn
    public var order: SortOrder

    public init(_ column: PluginColumn, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    public func compare(_ a: PluginRow, _ b: PluginRow) -> ComparisonResult {
        if let emptyA = isEmpty(a), let emptyB = isEmpty(b), emptyA != emptyB { return emptyA ? .orderedDescending : .orderedAscending }
        let r = base(a, b)
        return order == .forward ? r : (r == .orderedAscending ? .orderedDescending : r == .orderedDescending ? .orderedAscending : r)
    }

    /// nil: the column has no notion of "empty".
    private func isEmpty(_ r: PluginRow) -> Bool? {
        switch column {
        case .vendor: return r.vendor.isEmpty
        case .version: return r.version.isEmpty
        case .file: return r.path.isEmpty
        case .lastUsed: return r.lastUsed == nil
        default: return nil
        }
    }

    private func base(_ a: PluginRow, _ b: PluginRow) -> ComparisonResult {
        let byName = { PluginSort.text(a.name, b.name) }
        switch column {
        case .name: return byName()
        case .vendor: return then(PluginSort.text(a.vendor, b.vendor), byName)
        case .fxType: return then(PluginSort.text(a.fxType, b.fxType), byName)
        case .format: return then(PluginSort.text(a.format, b.format), byName)
        case .sets: return then(PluginSort.number(a.sets, b.sets), byName)
        case .lastUsed: return then(PluginSort.number(a.lastUsed?.timeIntervalSince1970 ?? 0, b.lastUsed?.timeIntervalSince1970 ?? 0), byName)
        case .version: return then(PluginSort.compareVersion(a.version, b.version), byName)
        case .file: return then(PluginSort.text(a.path, b.path), byName)
        case .status: return then(PluginSort.number(a.status.rawValue, b.status.rawValue), byName)
        }
    }

    private func then(_ r: ComparisonResult, _ next: () -> ComparisonResult) -> ComparisonResult {
        r == .orderedSame ? next() : r
    }

    static func text(_ a: String, _ b: String) -> ComparisonResult { a.localizedCaseInsensitiveCompare(b) }

    static func number<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    /// Versions are compared as numbers rather than as strings: character by character "12.4.3"
    /// comes out less than "9.7.2", because "1" comes before "9".
    static func compareVersion(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: "."), pb = b.split(separator: ".")
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? leadingNumber(pa[i]) : 0, vb = i < pb.count ? leadingNumber(pb[i]) : 0
            if va != vb { return va < vb ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func leadingNumber(_ s: Substring) -> Int { Int(s.prefix { $0.isNumber }) ?? 0 }
}
