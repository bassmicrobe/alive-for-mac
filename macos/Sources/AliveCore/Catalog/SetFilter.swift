// Port of src/SetFilter.cs
import Foundation

/// The set of conditions for the sets list. An empty condition filters nothing out, so "no
/// filters" and "filters reset" are one and the same state.
public struct SetFilter: Equatable, Sendable {
    /// By modification date (local calendar time).
    public var from: Date?
    public var to: Date?
    /// `SetEntry.shortVersion`, "12.4.3".
    public var versions: [String] = []
    /// 0..11 (C..B); `noKey` — a set with no key; `anyKey` — it has one at all.
    public var keyRoots: [Int] = []
    /// Scale indices.
    public var keyScales: [Int] = []
    /// Project tags, any of the selected ones.
    public var tags: [String] = []
    public var tracksMin = -1
    public var tracksMax = -1
    public var pluginsMin = -1
    public var pluginsMax = -1
    /// None of the three means "any".
    public var filesComplete = false
    public var filesMissing = false
    public var filesUnreadable = false
    /// Only sets with holes in their plugins.
    public var pluginsMissingOnly = false
    /// Only sets where everything is installed.
    public var pluginsAllInstalled = false
    public var previewHasRenders = false
    public var previewNoRenders = false

    public static let noKey = -1
    public static let anyKey = -2

    public init() {}

    /// Condition groups `matches` can leave out, for the facets of the filter window (an option
    /// is greyed when no set would remain if it were picked, judged without its own group).
    public struct Ignore: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let versions = Ignore(rawValue: 1)
        public static let keyRoots = Ignore(rawValue: 2)
        public static let keyScales = Ignore(rawValue: 4)
        public static let pluginsState = Ignore(rawValue: 8)
        public static let fileState = Ignore(rawValue: 16)
        public static let renders = Ignore(rawValue: 32)
        public static let tags = Ignore(rawValue: 64)
    }

    public var isEmpty: Bool { activeCount == 0 }

    /// How many condition groups are on — this number sits on the Filters button.
    public var activeCount: Int {
        var n = 0
        if from != nil || to != nil { n += 1 }
        if !versions.isEmpty { n += 1 }
        if !keyRoots.isEmpty || !keyScales.isEmpty { n += 1 }
        if !tags.isEmpty { n += 1 }
        if tracksMin >= 0 || tracksMax >= 0 { n += 1 }
        if pluginsMin >= 0 || pluginsMax >= 0 || pluginsMissingOnly || pluginsAllInstalled { n += 1 }
        if filesComplete || filesMissing || filesUnreadable { n += 1 }
        if previewHasRenders || previewNoRenders { n += 1 }
        return n
    }

    /// `tagsOf` maps a project folder to its tags. Tags live in a separate file (notes.cfg)
    /// rather than in the set, so they are only asked for when the tag filter is on.
    public func matches(_ s: SetEntry, tagsOf: (String) -> [String], ignoring skip: Ignore = []) -> Bool {
        if let from, s.modified < from { return false }
        if let to, s.modified > to { return false }

        if !skip.contains(.versions), !versions.isEmpty, !versions.contains(s.shortVersion) { return false }

        // Keys are compared by number, not by text: "C#" and "Db" are one note, and how it gets
        // written depends on the PreferFlatRootNote box in the set itself.
        if !skip.contains(.keyRoots), !keyRoots.isEmpty {
            let ok = keyRoots.contains(s.scaleRoot) || (s.scaleRoot >= 0 && keyRoots.contains(Self.anyKey))
            if !ok { return false }
        }
        if !skip.contains(.keyScales), !keyScales.isEmpty, !keyScales.contains(s.scaleIndex) { return false }

        // Several tags mean "or", just like versions.
        if !skip.contains(.tags), !tags.isEmpty {
            let own = tagsOf(s.projectDir)
            if !own.contains(where: { tags.contains($0) }) { return false }
        }

        if tracksMin >= 0, s.tracks < tracksMin { return false }
        if tracksMax >= 0, s.tracks > tracksMax { return false }
        if pluginsMin >= 0, s.plugins.count < pluginsMin { return false }
        if pluginsMax >= 0, s.plugins.count > pluginsMax { return false }

        if !skip.contains(.pluginsState) {
            if pluginsMissingOnly, s.missingPlugins == 0 { return false }
            if pluginsAllInstalled, s.missingPlugins > 0 { return false }
        }

        if !skip.contains(.fileState), filesComplete || filesMissing || filesUnreadable {
            let state = Self.fileState(of: s)
            let ok = (filesComplete && state == .complete) || (filesMissing && state == .missing)
                || (filesUnreadable && state == .unreadable)
            if !ok { return false }
        }

        if !skip.contains(.renders), previewHasRenders || previewNoRenders {
            if !((previewHasRenders && s.hasRenders) || (previewNoRenders && !s.hasRenders)) { return false }
        }
        return true
    }

    public enum FileState: Sendable { case complete, missing, unreadable }

    public static func fileState(of s: SetEntry) -> FileState {
        if !s.error.isEmpty { return .unreadable }
        return s.missingFiles > 0 ? .missing : .complete
    }

    public mutating func clear() { self = SetFilter() }

    // MARK: - Dates and counts

    /// Parses a date leniently: "2026" is the whole year, "2026-08" the whole month,
    /// "2026-08-07" the day. For an upper bound the end of the period is taken, or "up to 2026"
    /// would cut off everything past the first of January.
    public static func parseDate(_ text: String?, upperBound: Bool, calendar: Calendar = .current) -> Date? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        if t.isEmpty { return nil }

        let parts = t.split(separator: "-", omittingEmptySubsequences: false)
        guard let year = Int(parts[0].trimmingCharacters(in: .whitespaces)), (1900...2200).contains(year) else { return nil }
        let month = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
        let day = parts.count > 2 ? Int(parts[2].trimmingCharacters(in: .whitespaces)) : nil
        if let month, !(1...12).contains(month) { return nil }

        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date? {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))
        }
        let m = month ?? 1
        guard let first = date(year, m, 1) else { return nil }
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 31
        if let day, !(1...daysInMonth).contains(day) { return nil }

        if !upperBound { return date(year, m, day ?? 1) }
        guard month != nil else { return date(year, 12, 31, 23, 59, 59) }
        guard let day else { return date(year, m, daysInMonth, 23, 59, 59) }
        return date(year, m, day, 23, 59, 59)
    }

    /// "2026-08-07", or "" for none.
    public static func formatDate(_ d: Date?, calendar: Calendar = .current) -> String {
        guard let d else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// A number from the field; empty or junk means "no limit".
    public static func parseCount(_ text: String?) -> Int {
        guard let text, let v = Int(text.trimmingCharacters(in: .whitespaces)) else { return -1 }
        return v < 0 ? -1 : v
    }

    public static func formatCount(_ v: Int) -> String { v < 0 ? "" : String(v) }

    // MARK: - Versions

    /// Compares "12.4.3" style versions numerically, part by part ("6b3" counts as 6).
    public static func compareVersion(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".", omittingEmptySubsequences: false)
        let pb = b.split(separator: ".", omittingEmptySubsequences: false)
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? leadingNumber(pa[i]) : 0
            let vb = i < pb.count ? leadingNumber(pb[i]) : 0
            if va != vb { return va < vb ? .orderedAscending : .orderedDescending }
        }
        return a.caseInsensitiveCompare(b)
    }

    private static func leadingNumber(_ s: Substring) -> Int {
        var v = 0
        for ch in s {
            guard let d = ch.wholeNumberValue, ch.isASCII else { break }
            v = v &* 10 &+ d
        }
        return v
    }
}

/// What the filter window offers: only the values that occur in the sets, and which of them
/// would still leave something (upstream FiltersDialog: BuildKeyOptions / UpdateFacets).
public struct SetFilterFacets: Equatable, Sendable {
    /// Live versions present, newest first.
    public var versions: [String] = []
    /// Key roots present: `anyKey` and `noKey` first when they apply, then 0..11.
    public var roots: [Int] = []
    /// Scale indices present.
    public var scales: [Int] = []
    /// Tags on these sets, alphabetical.
    public var tags: [String] = []

    /// Options that would leave nothing under the rest of the filter.
    public var disabledVersions: Set<String> = []
    public var disabledRoots: Set<Int> = []
    public var disabledScales: Set<Int> = []
    public var disabledTags: Set<String> = []

    public var canPickMissingPlugins = false
    public var canPickAllInstalled = false
    public var canPickComplete = false
    public var canPickMissingFiles = false
    public var canPickUnreadable = false
    public var canPickHasRenders = false
    public var canPickNoRenders = false

    /// How many sets pass the whole filter.
    public var matches = 0

    public init() {}

    public static func make(sets: [SetEntry], filter f: SetFilter, tagsOf: (String) -> [String]) -> SetFilterFacets {
        var r = SetFilterFacets()
        var versions = Set<String>(), roots = Set<Int>(), scales = Set<Int>(), tags = Set<String>()
        var noKey = false
        for s in sets {
            if !s.shortVersion.isEmpty { versions.insert(s.shortVersion) }
            if s.scaleRoot < 0 { noKey = true } else if s.scaleRoot < 12 { roots.insert(s.scaleRoot) }
            if s.scaleIndex >= 0, s.scaleIndex < Scales.scaleCount { scales.insert(s.scaleIndex) }
            tags.formUnion(tagsOf(s.projectDir))
        }
        r.versions = versions.sorted { SetFilter.compareVersion($0, $1) == .orderedDescending }
        r.roots = (roots.isEmpty ? [] : [SetFilter.anyKey]) + (noKey ? [SetFilter.noKey] : []) + roots.sorted()
        r.scales = scales.sorted()
        r.tags = tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Facets: what is still possible with every OTHER group applied.
        var okVersions = Set<String>(), okRoots = Set<Int>(), okScales = Set<Int>(), okTags = Set<String>()
        for s in sets {
            if f.matches(s, tagsOf: tagsOf, ignoring: .versions), !s.shortVersion.isEmpty { okVersions.insert(s.shortVersion) }
            if f.matches(s, tagsOf: tagsOf, ignoring: .keyRoots) {
                okRoots.insert(s.scaleRoot)
                if s.scaleRoot >= 0 { okRoots.insert(SetFilter.anyKey) }
            }
            if f.matches(s, tagsOf: tagsOf, ignoring: .keyScales), s.scaleIndex >= 0 { okScales.insert(s.scaleIndex) }
            if f.matches(s, tagsOf: tagsOf, ignoring: .tags) { okTags.formUnion(tagsOf(s.projectDir)) }
            if f.matches(s, tagsOf: tagsOf, ignoring: .pluginsState) {
                if s.missingPlugins > 0 { r.canPickMissingPlugins = true } else { r.canPickAllInstalled = true }
            }
            if f.matches(s, tagsOf: tagsOf, ignoring: .fileState) {
                switch SetFilter.fileState(of: s) {
                case .complete: r.canPickComplete = true
                case .missing: r.canPickMissingFiles = true
                case .unreadable: r.canPickUnreadable = true
                }
            }
            if f.matches(s, tagsOf: tagsOf, ignoring: .renders) {
                if s.hasRenders { r.canPickHasRenders = true } else { r.canPickNoRenders = true }
            }
            if f.matches(s, tagsOf: tagsOf) { r.matches += 1 }
        }
        r.disabledVersions = Set(r.versions).subtracting(okVersions)
        r.disabledRoots = Set(r.roots).subtracting(okRoots)
        r.disabledScales = Set(r.scales).subtracting(okScales)
        r.disabledTags = Set(r.tags).subtracting(okTags)
        return r
    }
}
