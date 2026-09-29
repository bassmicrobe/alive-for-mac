// Port of MainForm.FillSets (src/MainForm.cs): catalog → search → filters → fold → sort → pinned first.
// Pure, so the whole pipeline is tested without a window.
import Foundation
import AliveCore

struct SetsPipeline {
    /// One row per project (or per set when not grouping), in display order.
    var heads: [SetEntry] = []
    /// The versions folded under a head, keyed by `key(forDirectory:)`, newest first. Only what
    /// passed the search and the filters — "show the rest" must show exactly that, not the whole
    /// folder from disk.
    var hidden: [String: [SetEntry]] = [:]

    struct Input {
        var sets: [SetEntry]
        var query = ""
        var filter = SetFilter()
        var groupByFolder = true
        var sort: SetSort?
        var pinnedFirst = false
        var pins: Set<String> = []
        var tagsOf: (String) -> [String] = { _ in [] }
        /// Whether the installed-plugin list could be read. When it could not, "missing" is not a
        /// fact but an unknown, so the missing/installed conditions are left out.
        var pluginsKnown = true
    }

    static func key(forDirectory dir: String) -> String { dir.lowercased() }

    /// The filter as it applies: without a readable plugin inventory the two plugin-state
    /// toggles cannot say anything true, so they filter nothing.
    static func effectiveFilter(_ filter: SetFilter, pluginsKnown: Bool) -> SetFilter {
        guard !pluginsKnown else { return filter }
        var f = filter
        f.pluginsMissingOnly = false
        f.pluginsAllInstalled = false
        return f
    }

    static func make(_ input: Input) -> SetsPipeline {
        let words = SetSearch.words(in: input.query)
        // Filter first and only then fold (a query for a name only an older version carries still
        // finds it).
        let filter = effectiveFilter(input.filter, pluginsKnown: input.pluginsKnown)
        var matched = input.sets.filter { set in
            filter.matches(set, tagsOf: input.tagsOf) && (words.isEmpty || SetSearch.matches(set, query: input.query))
        }
        var out = SetsPipeline()
        if input.groupByFolder {
            // The hidden versions are remembered BEFORE folding: afterwards the list of heads no
            // longer remembers whom it is holding under itself.
            let heads = ProjectIndex.collapseByFolder(matched)
            let headPaths = Set(heads.map(\.path))
            for var s in matched where !headPaths.contains(s.path) {
                s.collapsedCount = 0
                out.hidden[key(forDirectory: s.directory), default: []].append(s)
            }
            for key in out.hidden.keys {
                out.hidden[key]?.sort { $0.modified != $1.modified ? $0.modified > $1.modified : $0.path < $1.path }
            }
            matched = heads
        } else {
            // A "+N" counted while grouping was on must not stay hanging on every row.
            for i in matched.indices { matched[i].collapsedCount = 0 }
        }
        out.heads = ordered(matched, input)
        return out
    }

    private static func ordered(_ rows: [SetEntry], _ input: Input) -> [SetEntry] {
        let sort = input.sort ?? .fallback
        let tagsText: (SetEntry) -> String = { ProjectMeta.joinTags(input.tagsOf($0.projectDir)) }
        let pinSet: Set<String> = input.pinnedFirst ? Set(input.pins.map { $0.lowercased() }) : []

        // The direction reverses the comparison rather than the list after sorting: with the pinned
        // on top, reversing the list would turn the groups themselves around as well.
        func less(_ a: SetEntry, _ b: SetEntry) -> Bool {
            if input.pinnedFirst {
                let pa = pinSet.contains(a.path.lowercased()), pb = pinSet.contains(b.path.lowercased())
                if pa != pb { return pa }
            }
            let r = SetCompare.order(a, b, by: sort.column, tagsText: tagsText)
            if r != .orderedSame { return sort.descending ? r == .orderedDescending : r == .orderedAscending }
            return a.path < b.path      // deterministic among equals
        }
        return rows.sorted(by: less)
    }

    /// Every row in the order the table shows them, given which folders are open.
    func flattened(expanded: Set<String>) -> [SetEntry] {
        heads.flatMap { head -> [SetEntry] in
            let key = Self.key(forDirectory: head.directory)
            guard expanded.contains(key), let kids = hidden[key] else { return [head] }
            return [head] + kids
        }
    }

    /// The table row (0-based, in display order) that `path` occupies, or nil when it is not shown
    /// (filtered out, or folded under a row that is not open).
    func rowIndex(of path: String, expanded: Set<String>) -> Int? {
        flattened(expanded: expanded).firstIndex { $0.path == path }
    }

    /// The head row that stands for `path` (the row itself, or the row it is folded under).
    func head(containing path: String) -> SetEntry? {
        if let h = heads.first(where: { $0.path == path }) { return h }
        for (key, kids) in hidden where kids.contains(where: { $0.path == path }) {
            if let h = heads.first(where: { Self.key(forDirectory: $0.directory) == key }) { return h }
        }
        return nil
    }
}
