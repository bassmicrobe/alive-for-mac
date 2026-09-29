// Port of src/PluginFilter.cs (+ the facet counting of src/PluginFiltersDialog.cs UpdateFacets).
// Mac addition: "AU" is a format of its own; "Other" is what is neither VST3, VST2 nor AU.
import Foundation

public struct PluginFilter: Equatable, Hashable, Sendable {
    public var statusInstalled = false
    public var statusOtherFormat = false
    public var statusMissing = false

    /// "VST3", "VST2", "AU", "Other".
    public var formats: Set<String> = []
    public var vendors: Set<String> = []
    public var categories: Set<String> = []

    /// nil: no bound.
    public var setsMin: Int?
    public var setsMax: Int?

    /// The stand-ins for a plugin whose developer / type is not known.
    public static let unknownVendor = "Unknown"
    public static let otherCategory = "Other"
    public static let formatNames = ["VST3", "VST2", "AU", "Other"]

    public init() {}

    public var hasStatus: Bool { statusInstalled || statusOtherFormat || statusMissing }

    /// How many of the filter's five kinds of condition are set — the Filters button's badge.
    public var activeCount: Int {
        var n = 0
        if hasStatus { n += 1 }
        if !formats.isEmpty { n += 1 }
        if !vendors.isEmpty { n += 1 }
        if !categories.isEmpty { n += 1 }
        if setsMin != nil || setsMax != nil { n += 1 }
        return n
    }

    public var isEmpty: Bool { activeCount == 0 }

    public mutating func clear() { self = PluginFilter() }

    /// Which conditions to leave out — the sheet asks "what would remain if this one were not set"
    /// to grey out choices that cannot match anything.
    public struct Ignoring: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let status = Ignoring(rawValue: 1)
        public static let formats = Ignoring(rawValue: 2)
        public static let vendors = Ignoring(rawValue: 4)
        public static let categories = Ignoring(rawValue: 8)
    }

    public func matches(_ st: PluginStat, ignoring skip: Ignoring = []) -> Bool {
        if !skip.contains(.status), hasStatus, !statusPasses(st.match) { return false }
        if !skip.contains(.formats), !formats.isEmpty, !formats.contains(Self.formatGroup(of: st)) { return false }
        if !skip.contains(.vendors), !vendors.isEmpty,
           !Self.contains(vendors, Self.vendorKey(st)) { return false }
        if !skip.contains(.categories), !categories.isEmpty,
           !Self.contains(categories, Self.categoryKey(st)) { return false }
        if let lo = setsMin, st.sets < lo { return false }
        if let hi = setsMax, st.sets > hi { return false }
        return true
    }

    private func statusPasses(_ m: MatchKind) -> Bool {
        switch m {
        case .exact: return statusInstalled
        case .otherFormat: return statusOtherFormat
        case .missing: return statusMissing
        case .unknown: return false
        }
    }

    // MARK: keys

    /// "VST3" / "VST2" / "AU" / "Other".
    public static func formatGroup(of st: PluginStat) -> String {
        let f = st.format.uppercased()
        return ["VST3", "VST2", "AU"].contains(f) ? f : "Other"
    }

    public static func vendorKey(_ st: PluginStat) -> String { st.vendor.isEmpty ? unknownVendor : st.vendor }
    public static func categoryKey(_ st: PluginStat) -> String { st.fxType.isEmpty ? otherCategory : st.fxType }

    /// The sets of names are compared ignoring case, like upstream's OrdinalIgnoreCase sets.
    private static func contains(_ set: Set<String>, _ value: String) -> Bool {
        set.contains(value) || set.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

/// What the filter sheet needs to grey out and count: how many plugins each choice would leave,
/// given the other conditions.
public struct PluginFacets: Equatable, Sendable {
    /// Plugins passing every condition.
    public var matches = 0
    /// Per status, ignoring the status conditions.
    public var installed = 0, otherFormat = 0, missing = 0
    /// Per format group ("VST3"…), ignoring the format conditions.
    public var formatCounts: [String: Int] = [:]
    /// Lowercased vendors / categories that still occur, ignoring their own conditions.
    public var reachableVendors: Set<String> = []
    public var reachableCategories: Set<String> = []

    public init() {}

    public static func compute(_ filter: PluginFilter, over stats: [PluginStat]) -> PluginFacets {
        var f = PluginFacets()
        for st in stats {
            if filter.matches(st) { f.matches += 1 }
            if filter.matches(st, ignoring: .status) {
                switch st.match {
                case .exact: f.installed += 1
                case .otherFormat: f.otherFormat += 1
                case .missing: f.missing += 1
                case .unknown: break
                }
            }
            if filter.matches(st, ignoring: .formats) { f.formatCounts[PluginFilter.formatGroup(of: st), default: 0] += 1 }
            if filter.matches(st, ignoring: .vendors) { f.reachableVendors.insert(PluginFilter.vendorKey(st).lowercased()) }
            if filter.matches(st, ignoring: .categories) { f.reachableCategories.insert(PluginFilter.categoryKey(st).lowercased()) }
        }
        return f
    }

    public func canPick(vendor: String) -> Bool { reachableVendors.contains(vendor.lowercased()) }
    public func canPick(category: String) -> Bool { reachableCategories.contains(category.lowercased()) }

    /// The choices of the two tag fields: what occurs, sorted, with the "unknown" stand-ins last
    /// (only when something needs them).
    public static func vendorOptions(_ stats: [PluginStat]) -> [String] {
        options(stats.map { $0.vendor }, stand: PluginFilter.unknownVendor)
    }

    public static func categoryOptions(_ stats: [PluginStat]) -> [String] {
        options(stats.map { $0.fxType }, stand: PluginFilter.otherCategory)
    }

    private static func options(_ values: [String], stand: String) -> [String] {
        var seen = Set<String>(), out: [String] = [], hasBlank = false
        for v in values {
            if v.isEmpty { hasBlank = true; continue }
            if seen.insert(v.lowercased()).inserted { out.append(v) }
        }
        out.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if hasBlank, !seen.contains(stand.lowercased()) { out.append(stand) }
        return out
    }
}
