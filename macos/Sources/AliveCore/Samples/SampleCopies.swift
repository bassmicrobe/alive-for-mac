// Port of SampleCopies (src/SampleUsage.cs)
import Foundation

/// The same sample in more than one place of the library: equal name, size and content hash
/// (`SampleFile.print` — name and size alone also pair a pack's Dry and Wet takes of one sound).
/// The typical case is a pack unpacked twice, or the same one-shots shipped in several packs. A
/// file without a print is never anybody's copy: telling a person that two different sounds are
/// one is worse than missing a copy.
public struct SampleCopies: Sendable {
    public static let empty = SampleCopies()

    /// Every file that has a copy maps to its group's number in `groups`.
    private var groupOf: [Int: Int] = [:]
    private var groups: [[Int]] = []
    private var filesByFolder: [Int: Int] = [:]
    private var bytesByFolder: [Int: Int64] = [:]

    /// Every file with a copy, the group that wastes the most room first and its copies side by
    /// side — the Duplicates lens as it is.
    public private(set) var files: [Int] = []
    /// What the copies take beyond one of each.
    public private(set) var extraBytes: Int64 = 0

    public init() {}

    /// The other places this very sample lies in; empty — it is the only one.
    public func others(of file: Int) -> [Int] {
        guard let g = groupOf[file] else { return [] }
        return groups[g].filter { $0 != file }
    }

    /// In how many other places this sample lies; 0 — nowhere else.
    public func copies(of file: Int) -> Int {
        groupOf[file].map { groups[$0].count - 1 } ?? 0
    }

    /// How many samples of a folder's subtree lie somewhere else too, and what they weigh.
    public func files(in folder: Int) -> Int { filesByFolder[folder] ?? 0 }
    public func bytes(in folder: Int) -> Int64 { bytesByFolder[folder] ?? 0 }

    /// `isCancelled` is polled every few thousand files and groups; once it is true the partial
    /// result is returned at once, for the caller to discard.
    public static func find(in index: SampleIndex, isCancelled: () -> Bool = { false }) -> SampleCopies {
        var c = SampleCopies()
        guard !index.files.isEmpty else { return c }

        var byKey: [String: [Int]] = [:]
        for (i, f) in index.files.enumerated() where f.print != 0 {
            if i % 4096 == 0, isCancelled() { return c }
            byKey["\(f.size)|\(f.print)|\(f.name.lowercased())", default: []].append(i)
        }

        var found = byKey.values.filter { $0.count > 1 && index.files[$0[0]].size > 0 }
        func waste(_ g: [Int]) -> Int64 { index.files[g[0]].size * Int64(g.count - 1) }
        func name(_ g: [Int]) -> String { index.files[g[0]].name }
        found.sort { a, b in
            let wa = waste(a), wb = waste(b)
            if wa != wb { return wa > wb }
            let r = name(a).localizedCaseInsensitiveCompare(name(b))
            return r == .orderedSame ? a[0] < b[0] : r == .orderedAscending
        }

        var done = 0
        for var g in found {
            done += 1
            if done % 1024 == 0, isCancelled() { return c }
            c.extraBytes += waste(g)
            g.sort { a, b in
                let pa = index.folders[index.files[a].folder].path, pb = index.folders[index.files[b].folder].path
                let r = pa.localizedCaseInsensitiveCompare(pb)
                return r == .orderedSame ? a < b : r == .orderedAscending
            }
            let number = c.groups.count
            c.groups.append(g)
            c.files.append(contentsOf: g)
            for f in g {
                c.groupOf[f] = number
                var d: Int? = index.files[f].folder
                while let x = d {
                    c.filesByFolder[x, default: 0] += 1
                    c.bytesByFolder[x, default: 0] += index.files[f].size
                    d = index.folders[x].parent
                }
            }
        }
        return c
    }
}
