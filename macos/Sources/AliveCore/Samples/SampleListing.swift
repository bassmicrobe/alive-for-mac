// Port of the row building of src/SamplesTab.cs: AddTree, FlatRows, sorting, SearchCap
import Foundation

public struct SampleSort: Equatable, Sendable {
    public var column: SampleColumn?
    public var descending: Bool

    public init(column: SampleColumn? = nil, descending: Bool = false) {
        self.column = column
        self.descending = descending
    }
}

/// One row of the list: a folder or a sample, and how deep it stands in the tree. Its id is its
/// path, so a selection survives a fresh index.
public struct SampleRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case folder(Int)
        case file(Int)
    }

    public let id: String
    public let kind: Kind
    public let depth: Int
}

/// Names lowercased once per index: a search runs on every letter typed over up to a couple of
/// hundred thousand names.
public struct SampleNameKeys: Sendable {
    let folders: [String]
    let files: [String]

    public init(_ index: SampleIndex) {
        folders = index.folders.map { $0.name.lowercased() }
        files = index.files.map { $0.name.lowercased() }
    }
}

public struct SampleListing: Sendable {
    public var rows: [SampleRow] = []
    /// How many things matched in a flat list before the cut (`rows.count` when none was made).
    public var matches = 0
    public var isFlat = false

    public var isCut: Bool { matches > rows.count }
}

public enum SampleLister {
    /// A query like "a" matches most of the library, and a table of a hundred thousand rows helps
    /// nobody. The cut is said by the counter.
    public static let searchCap = 5000

    public static func isFlat(lens: SampleLens, query: String) -> Bool {
        lens != .all || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `open` — lowercased paths of the folders shown open in the tree.
    public static func listing(index: SampleIndex, usage: SampleUsage, copies: SampleCopies,
                               lens: SampleLens, sort: SampleSort, open: Set<String>, query: String,
                               keys: SampleNameKeys? = nil, cap: Int = searchCap) -> SampleListing {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let ctx = Context(index: index, usage: usage, copies: copies, sort: sort)
        var out = SampleListing()

        guard isFlat(lens: lens, query: query) else {
            for r in ctx.sortedFolders(index.roots, isRoot: true) { ctx.addTree(&out.rows, r, 0, open) }
            out.matches = out.rows.count
            return out
        }
        out.isFlat = true

        var folders: [Int] = []
        var files: [Int] = []
        switch lens {
        case .neverUsed: folders = usage.neverUsed(in: index)
        case .mostUsed: files = usage.usedFiles
        case .duplicates: files = copies.files
        case .all:
            // A search over the whole library; the roots are not matched — their "name" is a path.
            let rootSet = Set(index.roots)
            folders = index.folders.indices.filter { !rootSet.contains($0) }
            files = Array(index.files.indices)
        }
        if !q.isEmpty {
            let k = keys ?? SampleNameKeys(index)
            folders = folders.filter { k.folders[$0].contains(q) }
            files = files.filter { k.files[$0].contains(q) }
        }

        out.matches = folders.count + files.count
        // The cut goes before the sort: ordering a hundred thousand names on every letter typed
        // would be the slow part, and whoever sees "first 5000" types another letter.
        if folders.count > cap { folders = Array(folders.prefix(cap)) }
        if files.count > cap - folders.count { files = Array(files.prefix(max(0, cap - folders.count))) }

        if sort.column == nil && lens == .neverUsed {
            folders.sort { index.folders[$0].totalBytes > index.folders[$1].totalBytes }
        } else {
            folders = ctx.sortedFolders(folders, isRoot: false)
        }
        // Duplicates keep the copies' order: the most room wasted first, copies side by side.
        if lens == .mostUsed && sort.column == nil {
            files.sort { usage.compareUse($0, $1, in: index) }
        } else if lens != .duplicates || sort.column != nil {
            files = ctx.sortedFiles(files)
        }

        out.rows = folders.map { ctx.folderRow($0, 0) } + files.map { ctx.fileRow($0, 0) }
        return out
    }

    /// Lowercased paths of every folder from `folder` up to its root — what must be open for the
    /// folder to show in the tree.
    public static func ancestors(of folder: Int?, in index: SampleIndex) -> Set<String> {
        var s = Set<String>()
        var f = folder
        while let x = f {
            s.insert(index.folders[x].path.lowercased())
            f = index.folders[x].parent
        }
        return s
    }

    // MARK: - ordering

    private struct Context {
        let index: SampleIndex
        let usage: SampleUsage
        let copies: SampleCopies
        let sort: SampleSort

        func folderRow(_ f: Int, _ depth: Int) -> SampleRow {
            SampleRow(id: index.folders[f].path, kind: .folder(f), depth: depth)
        }

        func fileRow(_ f: Int, _ depth: Int) -> SampleRow {
            SampleRow(id: index.path(of: f), kind: .file(f), depth: depth)
        }

        func addTree(_ rows: inout [SampleRow], _ d: Int, _ depth: Int, _ open: Set<String>) {
            rows.append(folderRow(d, depth))
            guard open.contains(index.folders[d].path.lowercased()) else { return }
            for c in sortedFolders(index.folders[d].children, isRoot: false) { addTree(&rows, c, depth + 1, open) }
            for f in sortedFiles(index.folders[d].files) { rows.append(fileRow(f, depth + 1)) }
        }

        func natural(_ a: String, _ b: String) -> ComparisonResult { a.localizedStandardCompare(b) }

        /// With no column chosen the roots keep the order they were added in.
        func sortedFolders(_ list: [Int], isRoot: Bool) -> [Int] {
            guard let column = sort.column else {
                return isRoot ? list : list.sorted { natural(index.folders[$0].name, index.folders[$1].name) == .orderedAscending }
            }
            return list.sorted { a, b in
                let r = compareFolders(a, b, column)
                if r == .orderedSame { return natural(index.folders[a].name, index.folders[b].name) == .orderedAscending }
                return sort.descending ? r == .orderedDescending : r == .orderedAscending
            }
        }

        func sortedFiles(_ list: [Int]) -> [Int] {
            guard let column = sort.column else {
                return list.sorted { natural(index.files[$0].name, index.files[$1].name) == .orderedAscending }
            }
            let desc = sort.descending && column != .samples && column != .used
            return list.sorted { a, b in
                let r = compareFiles(a, b, column)
                if r == .orderedSame { return natural(index.files[a].name, index.files[b].name) == .orderedAscending }
                return desc ? r == .orderedDescending : r == .orderedAscending
            }
        }

        private func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
            a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }

        private func compareFolders(_ a: Int, _ b: Int, _ c: SampleColumn) -> ComparisonResult {
            let fa = index.folders[a], fb = index.folders[b]
            let ua = usage.of(folder: a), ub = usage.of(folder: b)
            switch c {
            case .name: return natural(fa.name, fb.name)
            case .location: return natural(index.location(of: fa.parent), index.location(of: fb.parent))
            case .samples: return cmp(fa.totalSamples, fb.totalSamples)
            case .used: return cmp(ua?.used ?? 0, ub?.used ?? 0)
            case .projects: return cmp(ua?.projects ?? 0, ub?.projects ?? 0)
            case .lastUsed: return cmp(ua?.lastUsed ?? .distantPast, ub?.lastUsed ?? .distantPast)
            case .size: return cmp(fa.totalBytes, fb.totalBytes)
            case .copies: return cmp(copies.files(in: a), copies.files(in: b))
            case .created: return cmp(fa.created ?? .distantPast, fb.created ?? .distantPast)
            case .modified: return cmp(fa.modified ?? .distantPast, fb.modified ?? .distantPast)
            }
        }

        private func compareFiles(_ a: Int, _ b: Int, _ c: SampleColumn) -> ComparisonResult {
            let fa = index.files[a], fb = index.files[b]
            let ua = usage.of(file: a), ub = usage.of(file: b)
            switch c {
            case .location:
                return natural(index.location(of: fa.folder), index.location(of: fb.folder))
            case .projects: return cmp(ua?.projects ?? 0, ub?.projects ?? 0)
            case .lastUsed: return cmp(ua?.lastUsed ?? .distantPast, ub?.lastUsed ?? .distantPast)
            case .size: return cmp(fa.size, fb.size)
            case .copies: return cmp(copies.copies(of: a), copies.copies(of: b))
            case .created: return cmp(fa.created ?? .distantPast, fb.created ?? .distantPast)
            case .modified: return cmp(fa.modified ?? .distantPast, fb.modified ?? .distantPast)
            case .name, .samples, .used: return natural(fa.name, fb.name)
            }
        }
    }
}
