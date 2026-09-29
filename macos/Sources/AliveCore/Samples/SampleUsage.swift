// Port of SampleUse, FolderUse and SampleUsage (src/SampleUsage.cs)
import Foundation

/// How one sample of the library is used: by which sets, in how many projects, and when last.
public struct SampleUse: Sendable {
    public var sets: [SetEntry] = []
    public var projects = 0
    /// The newest `modified` of the sets that use it (`.distantPast` — never).
    public var lastUsed = Date.distantPast

    /// Notes one more set; false when it was already there.
    mutating func add(_ s: SetEntry) -> Bool {
        if s.modified > lastUsed { lastUsed = s.modified }
        guard !sets.contains(where: { $0.path == s.path }) else { return false }
        sets.append(s)
        return true
    }
}

/// The same over a folder's whole subtree.
public struct FolderUse: Sendable {
    /// Distinct samples of the subtree used at least once.
    public var used = 0
    public var projects = 0
    public var lastUsed = Date.distantPast
}

/// Which samples of the library the sets use. Counted by PROJECTS — distinct `SetEntry.projectDir`
/// — rather than by .als files: ten versions of one track are one use.
///
/// A path inside a root of the library is looked up directly. A path outside it may be a copy —
/// Collect All puts one into the project's Samples/Imported — so it is matched by size and name.
/// Several files of the library with the same size and name all count as used: each of them holds
/// the sound that plays in the track.
public struct SampleUsage: Sendable {
    public static let empty = SampleUsage()

    private var byFile: [Int: SampleUse] = [:]
    private var byFolder: [Int: FolderUse] = [:]
    private var bySet: [String: [Int]] = [:]

    public init() {}

    public func of(file: Int) -> SampleUse? { byFile[file] }
    public func of(folder: Int) -> FolderUse? { byFolder[folder] }

    /// The used samples (positions in `SampleIndex.files`), unordered.
    public var usedFiles: [Int] { Array(byFile.keys) }
    public var usedCount: Int { byFile.count }

    /// The library samples one set uses — the other way round from `of(file:)`.
    public func files(ofSet path: String) -> [Int] { bySet[path] ?? [] }

    public static func compute(index: SampleIndex, sets: [SetEntry]) -> SampleUsage {
        var u = SampleUsage()
        guard !index.files.isEmpty, !sets.isEmpty else { return u }

        let folderByPath = index.folderLookup()
        let rootPrefixes = index.roots.map { r -> String in
            let p = index.folders[r].path.lowercased()
            return p.hasSuffix("/") ? p : p + "/"
        }

        // Sizes of audio files are nearly unique, so a list is made only where two files do
        // share one — a list per file would cost a few hundred thousand objects.
        var bySize: [Int64: [Int]] = [:]
        for (i, f) in index.files.enumerated() { bySize[f.size, default: []].append(i) }

        // A folder's names are indexed only once somebody lands in it.
        var names: [Int: [String: Int]] = [:]
        var projects: [Int: Set<String>] = [:]
        var hits: [Int] = []

        for s in sets {
            let project = s.projectDir.lowercased()
            for (i, raw) in s.samples.enumerated() {
                hits.removeAll(keepingCapacity: true)
                let p = raw.lowercased()
                if rootPrefixes.contains(where: { p.hasPrefix($0) }) {
                    direct(p, index, folderByPath, &names, &hits)
                } else {
                    copies(p, i < s.sampleSizes.count ? s.sampleSizes[i] : 0, index, bySize, &hits)
                }
                for f in hits {
                    if u.byFile[f, default: SampleUse()].add(s) { u.bySet[s.path, default: []].append(f) }
                    projects[f, default: []].insert(project)
                }
            }
        }

        // Up the folders, from every used file to its root. Sets of projects are made only on the
        // folders of these chains.
        var folderProjects: [Int: Set<String>] = [:]
        for (f, use) in u.byFile {
            let mine = projects[f] ?? []
            u.byFile[f]?.projects = mine.count
            var d: Int? = index.files[f].folder
            while let x = d {
                var fu = u.byFolder[x] ?? FolderUse()
                fu.used += 1
                if use.lastUsed > fu.lastUsed { fu.lastUsed = use.lastUsed }
                u.byFolder[x] = fu
                folderProjects[x, default: []].formUnion(mine)
                d = index.folders[x].parent
            }
        }
        for (d, set) in folderProjects { u.byFolder[d]?.projects = set.count }
        return u
    }

    /// `p` is lowercased.
    private static func direct(_ p: String, _ index: SampleIndex, _ folderByPath: [String: Int],
                               _ names: inout [Int: [String: Int]], _ hits: inout [Int]) {
        guard let slash = p.lastIndex(of: "/"), slash != p.startIndex,
              let dir = folderByPath[String(p[..<slash])] else { return }
        if names[dir] == nil {
            var map: [String: Int] = [:]
            for fi in index.folders[dir].files { map[index.files[fi].name.lowercased()] = fi }
            names[dir] = map
        }
        if let hit = names[dir]?[String(p[p.index(after: slash)...])] { hits.append(hit) }
    }

    private static func copies(_ p: String, _ size: Int64, _ index: SampleIndex, _ bySize: [Int64: [Int]],
                               _ hits: inout [Int]) {
        guard size > 0, let same = bySize[size] else { return }
        let name = p.lastIndex(of: "/").map { String(p[p.index(after: $0)...]) } ?? p
        for f in same where index.files[f].name.lowercased() == name { hits.append(f) }
    }

    // MARK: views

    /// More projects first, then the more recently used, then by name.
    public func compareUse(_ a: Int, _ b: Int, in index: SampleIndex) -> Bool {
        let ua = byFile[a], ub = byFile[b]
        let pa = ua?.projects ?? 0, pb = ub?.projects ?? 0
        if pa != pb { return pa > pb }
        let la = ua?.lastUsed ?? .distantPast, lb = ub?.lastUsed ?? .distantPast
        if la != lb { return la > lb }
        return index.files[a].name.localizedStandardCompare(index.files[b].name) == .orderedAscending
    }

    /// The used samples of a folder's subtree, the most used first.
    public func usedUnder(_ folder: Int, in index: SampleIndex) -> [Int] {
        guard byFolder[folder] != nil else { return [] }
        return byFile.keys.filter { index.folder(index.files[$0].folder, isWithin: folder) }
            .sorted { compareUse($0, $1, in: index) }
    }

    /// The topmost folders nothing is used from: unused themselves, while their parent is used
    /// (or there is no parent). These are the pieces that can go whole — listing every unused
    /// subfolder under them as well would only repeat them.
    public func neverUsed(in index: SampleIndex) -> [Int] {
        index.folders.indices.filter { i in
            let f = index.folders[i]
            guard f.totalSamples > 0, byFolder[i] == nil else { return false }
            return f.parent.map { byFolder[$0] != nil } ?? true
        }
    }

    /// The newest set of every project among the given ones, newest first — a project in a list
    /// stands under the name of its latest version.
    public static func newest(_ sets: [SetEntry]) -> [SetEntry] {
        var best: [String: SetEntry] = [:]
        for s in sets {
            let key = s.projectDir.lowercased()
            if let b = best[key], b.modified >= s.modified { continue }
            best[key] = s
        }
        return best.values.sorted { $0.modified > $1.modified }
    }
}
