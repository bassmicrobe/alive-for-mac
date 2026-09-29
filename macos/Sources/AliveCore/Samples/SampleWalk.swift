// Port of SampleIndex.Build / Walk / CountIn (src/SampleIndex.cs)
import Foundation

/// Counter shared by the parallel walks; the callback receives the running total.
private final class FoundCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    private let report: ((Int) -> Void)?

    init(_ report: ((Int) -> Void)?) { self.report = report }

    func add(_ n: Int) {
        lock.lock()
        total += n
        let now = total
        lock.unlock()
        report?(now)
    }
}

extension SampleIndex {
    /// Every switched-on root, side by side: they do not overlap (see `effective`) and usually sit
    /// on different drives, so walking them at once halves the wait on two disks.
    ///
    /// `previous` — the index this one replaces. An AIFF it already looked into, with the same
    /// path and size, keeps its `silent` flag without being opened again, and a content print is
    /// kept while size and date stay the same: a file that has not changed has nothing new to say.
    /// (The walk itself is repeated in full — listing folders is cheap; that is the incremental
    /// part upstream has too.)
    public static func build(roots: [String], disabled: [String], previous: SampleIndex? = nil,
                             progress: ((Int) -> Void)? = nil,
                             isCancelled: @escaping () -> Bool = { false }) -> SampleIndex {
        let walk = effective(roots, disabled: disabled)
        var known: [String: SampleFile] = [:]
        if let previous {
            for (i, f) in previous.files.enumerated() where AiffReader.isAiffName(f.name) || f.print != 0 {
                known[previous.path(of: i).lowercased()] = f
            }
        }
        let counter = FoundCounter(progress)
        let trees = Parallel.map(count: walk.count, isCancelled: isCancelled) { i in
            SampleIndex.walk(root: walk[i], known: known, found: counter.add, isCancelled: isCancelled)
        }
        var idx = SampleIndex.combining(trees.compactMap { $0 })
        if !isCancelled() { SamplePrints.take(&idx, known: known, isCancelled: isCancelled) }
        return idx
    }

    /// How many samples a folder holds, by the very rules of the walk — the number in a folders
    /// dialog must agree with the tab. -1: the folder would not open.
    public static func countIn(_ folder: String, isCancelled: @escaping () -> Bool = { false }) -> Int {
        guard let tree = walk(root: folder, known: nil, found: { _ in }, isCancelled: isCancelled) else { return -1 }
        return tree.folders[0].totalSamples
    }

    private struct Pending {
        let path: String
        let folder: Int        // where what is found here belongs
        let own: Bool          // false — weight only: counted into `folder`, never a node
    }

    /// One root. A stack rather than recursion — libraries run a dozen levels deep. nil: the root
    /// itself would not open, or the walk was called off.
    ///
    /// `known` — AIFFs looked into before; nil — do not look into AIFFs at all (`silent`): the
    /// index wants it, the count in a folders dialog does not. Only read here, so the parallel
    /// walks can share it. Symlinks and hidden entries are skipped by `FolderScan.list`; a package
    /// (a bundle such as .app or a project package) is walked for weight only.
    static func walk(root: String, known: [String: SampleFile]?, found: (Int) -> Void,
                     isCancelled: () -> Bool) -> SampleIndex? {
        let top = norm(root)
        var all = [SampleFolder()]
        all[0].path = top
        all[0].name = top
        let attrs = try? FileManager.default.attributesOfItem(atPath: top)
        all[0].created = attrs?[.creationDate] as? Date
        all[0].modified = attrs?[.modificationDate] as? Date

        var files: [SampleFile] = []
        var todo = [Pending(path: top, folder: 0, own: true)]
        var batch = 0
        var first = true

        while let p = todo.popLast() {
            if isCancelled() { return nil }
            guard let entries = FolderScan.list(p.path) else {
                if first { return nil }
                continue
            }
            first = false
            for e in entries.sorted(by: { $0.name < $1.name }) {
                if e.isDirectory {
                    let full = combine(p.path, e.name)
                    if !p.own || e.isPackage || isWeightOnly(e.name) {
                        todo.append(Pending(path: full, folder: p.folder, own: false))
                        continue
                    }
                    var child = SampleFolder()
                    child.path = full
                    child.name = e.name
                    child.parent = p.folder
                    child.created = e.created
                    child.modified = e.modified
                    all.append(child)
                    todo.append(Pending(path: full, folder: all.count - 1, own: true))
                    continue
                }

                all[p.folder].totalBytes += e.size      // own bytes for now; the subtree is added below
                guard p.own, isSampleName(e.name) else { continue }
                var f = SampleFile()
                f.name = e.name
                f.size = e.size
                f.folder = p.folder
                f.created = e.created
                f.modified = e.modified
                if let known, AiffReader.isAiffName(e.name) {
                    let full = combine(p.path, e.name)
                    if let was = known[full.lowercased()], was.size == e.size {
                        f.silent = was.silent
                    } else {
                        f.silent = !AiffReader.canRead(path: full)
                    }
                }
                files.append(f)
                all[p.folder].files.append(files.count - 1)
                batch += 1
                if batch == 256 { found(batch); batch = 0 }
            }
        }
        if batch > 0 { found(batch) }
        return finishTree(all, files)
    }

    /// Totals from the bottom up, then only the folders with a sample below them stay.
    private static func finishTree(_ folders: [SampleFolder], _ files: [SampleFile]) -> SampleIndex {
        var all = folders
        // A folder is always made after its parent, so going backwards finishes every child before
        // its parent takes it in.
        for i in stride(from: all.count - 1, through: 0, by: -1) {
            all[i].totalSamples += all[i].files.count
            guard let p = all[i].parent else { continue }
            all[p].totalSamples += all[i].totalSamples
            all[p].totalBytes += all[i].totalBytes
        }

        var newPos = [Int](repeating: -1, count: all.count)
        var kept: [SampleFolder] = []
        for (i, var f) in all.enumerated() where i == 0 || f.totalSamples > 0 {
            newPos[i] = kept.count
            f.parent = f.parent.map { newPos[$0] }
            f.children = []
            if let p = f.parent { kept[p].children.append(kept.count) }
            kept.append(f)
        }
        var out = SampleIndex()
        out.roots = [0]
        out.folders = kept
        out.files = files.map { var s = $0; s.folder = newPos[s.folder]; return s }
        return out
    }
}
