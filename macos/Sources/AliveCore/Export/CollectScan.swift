// Port of src/SampleScan.cs (only what Collect All needs: which media files a set requires and
// where they come from). Named Collect* so it can live beside the Samples slice's own types.
import Foundation

/// Where a media file a set refers to came from. The categories are the four "Collect All and
/// Save" has in Live, plus "already in the project": Live does not ask about those, they are in
/// place as they are.
public enum CollectOrigin: Sendable, CaseIterable {
    /// Inside the set's own folder — always copied when collecting.
    case inProject
    /// Inside somebody else's "* Project" folder.
    case otherProject
    /// The User Library.
    case userLibrary
    /// An installed pack, the Core Library or Builtin.
    case factoryPack
    /// Simply somewhere on disk.
    case elsewhere
    /// Not found.
    case missing
}

/// One media file a set needs — together with every reference leading to it.
///
/// A file, not a reference: one set points at its own Samples folder with hundreds of clips, and
/// on a real library 28,631 references boil down to roughly 1,100 distinct files. What has to be
/// copied and shown are files, while the reference numbers are needed later by the patcher —
/// every one of them has to be rewritten.
public struct CollectDependency: Sendable, Identifiable {
    /// Position in the scan's list: a stable key for plans.
    public var id = 0
    /// One of the references — the path and the pack name come from it.
    public var ref = FileRefInfo()
    /// Where it was found.
    public var resolved: ResolvedRef
    public var origin: CollectOrigin = .missing
    /// Filled in for `.factoryPack`.
    public var packName = ""
    /// From disk; 0 if it was not found or could not be counted.
    public var size: Int64 = 0
    /// .amxd (MxPatchRef) rather than a sample.
    public var isDevice = false
    /// FileRef numbers in document order — `AlsSamplePatch` addresses by them.
    public var refIndexes: [Int] = []

    public init(resolved: ResolvedRef) { self.resolved = resolved }

    public var path: String { resolved.resolvedPath }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Which media files a set needs and where they come from. Reads nothing from disk beyond what
/// `AlsFile` has already read (plus sizes), and writes nothing.
public enum CollectScan {
    /// `setDir` is the .als folder itself, not the project folder: `ProjectIndex` counts it the
    /// same way, and the two must not diverge, or "in the project" here and "lost" in the catalog
    /// would be talking about different things.
    public static func of(_ info: AlsInfo, setDir: String, env: LiveEnvironment,
                          isCancelled: () -> Bool = { false }) -> [CollectDependency] {
        var list: [CollectDependency] = []
        // Two levels of folding. First by the reference itself: identical references resolve
        // identically, and there is no point resolving 28 thousand times. Then by the path
        // found: different references (one through a pack, another by absolute path) lead to one
        // file, and it has to be copied once.
        var byRaw: [String: Int?] = [:]
        var byFile: [String: Int] = [:]
        let probe = ProbeCache()

        for (i, fr) in info.files.enumerated() {
            if i % 512 == 0, isCancelled() { break }
            let device = fr.container == "MxPatchRef"
            guard fr.isSampleDependency || device else { continue }

            let raw = "\(fr.relativePathType)|\(fr.relativePath)|\(fr.absolutePath)|\(fr.livePackName)"
            if let known = byRaw[raw] {
                if let idx = known { list[idx].refIndexes.append(i) }
                continue
            }
            let rr = RefResolver.resolve(fr, projectDir: setDir, env: env, probe: probe)
            if rr.status == .empty {
                byRaw[raw] = .some(nil)          // a blank — remembered so it is not resolved again
                continue
            }
            let fileKey = rr.status == .found
                ? rr.resolvedPath
                : "?" + (fr.relativePath.isEmpty ? fr.absolutePath : fr.relativePath)
            if let idx = byFile[fileKey] {
                list[idx].refIndexes.append(i)
                byRaw[raw] = .some(idx)
                continue
            }

            var dep = CollectDependency(resolved: rr)
            dep.id = list.count
            dep.ref = fr
            dep.isDevice = device
            dep.refIndexes = [i]
            let (origin, pack) = classify(rr, fr, setDir: setDir, env: env)
            dep.origin = origin
            dep.packName = pack
            dep.size = origin == .missing ? 0 : sizeOf(rr.resolvedPath)
            byRaw[raw] = .some(list.count)
            byFile[fileKey] = list.count
            list.append(dep)
        }
        return list
    }

    /// The order of the checks matters. "In the project" comes first: a project lying inside the
    /// User Library is still one's own project, and its samples are not "from the library".
    static func classify(_ rr: ResolvedRef, _ fr: FileRefInfo, setDir: String,
                         env: LiveEnvironment) -> (CollectOrigin, String) {
        guard rr.status == .found else {
            return (.missing, rr.status == .missingPack ? fr.livePackName : "")
        }
        let p = rr.resolvedPath
        if under(p, setDir) { return (.inProject, "") }

        if fr.relativePathType == 5, !fr.livePackName.isEmpty { return (.factoryPack, fr.livePackName) }
        for (name, root) in env.packs.sorted(by: { $0.key < $1.key }) where under(p, root) {
            return (.factoryPack, name)
        }
        if fr.relativePathType == 7 || under(p, env.builtin) || under(p, env.coreLibrary) {
            return (.factoryPack, "Core Library")
        }
        if fr.relativePathType == 6 || under(p, env.userLibrary) { return (.userLibrary, "") }
        if inSomeProject(p) { return (.otherProject, "") }
        return (.elsewhere, "")
    }

    /// Whether a path lies inside a root. Compared as whole components, or ".../Samples2" would
    /// pass for ".../Samples"; case-insensitive like a default macOS volume.
    static func under(_ path: String, _ root: String) -> Bool {
        relative(root: root, path: path) != nil
    }

    /// The path relative to a root, forward slashes; nil if it is not inside the root.
    static func relative(root: String, path: String) -> String? {
        guard !path.isEmpty, !root.isEmpty else { return nil }
        var a = URL(fileURLWithPath: root).standardized.path
        if !a.hasSuffix("/") { a += "/" }
        let b = URL(fileURLWithPath: path).standardized.path
        guard b.count > a.count, b.lowercased().hasPrefix(a.lowercased()) else { return nil }
        return String(b.dropFirst(a.count))
    }

    /// By the same rule as `SetEntry.projectDir`: no more than four levels up.
    static func inSomeProject(_ path: String) -> Bool {
        var d = (path as NSString).deletingLastPathComponent
        for _ in 0..<4 {
            if (d as NSString).lastPathComponent.lowercased().hasSuffix(" project") { return true }
            let parent = (d as NSString).deletingLastPathComponent
            if parent == d || parent.isEmpty { break }
            d = parent
        }
        return false
    }

    /// .adg and .amxd are sometimes folders — their size is the sum of the files inside, not 0.
    static func sizeOf(_ path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
        return dirSize(path, depth: 0)
    }

    /// The recursive sum of file sizes in a folder, walked by hand: an inaccessible subfolder
    /// only cuts the count short for itself. The depth limit stops a mounted loop.
    private static func dirSize(_ dir: String, depth: Int) -> Int64 {
        guard depth <= 4, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return 0 }
        var total: Int64 = 0
        for n in names {
            let p = (dir as NSString).appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir) else { continue }
            if isDir.boolValue { total += dirSize(p, depth: depth + 1); continue }
            total += ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        return total
    }
}
