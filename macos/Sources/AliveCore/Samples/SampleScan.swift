// Port of src/SampleScan.cs
import Foundation

/// Where a media file a set refers to came from. The categories are the same four "Collect All and
/// Save" has in Live, plus "already in the project": Live does not ask about those, they are in
/// place as it is.
public enum SampleOrigin: Sendable {
    /// Inside the set's own folder — always copied when collecting.
    case inProject
    /// Inside somebody else's "* Project" folder.
    case otherProject
    case userLibrary
    /// An installed pack, the Core Library or Builtin.
    case factoryPack
    /// Simply somewhere on disk.
    case elsewhere
    case missing
}

/// One media file a set needs — together with every reference leading to it.
///
/// A file, not a reference: one set points at its own Samples folder with hundreds of clips, and on
/// a real library 28,631 references boil down to roughly 1,100 distinct files. What has to be
/// copied and shown are files, while the reference numbers are needed later by a patcher — every
/// one of them has to be rewritten.
public struct SampleDep: Sendable {
    /// One of the references — the path and the pack name come from it.
    public var ref: FileRefInfo
    /// Where it was found.
    public var resolved: ResolvedRef
    public var origin: SampleOrigin = .missing
    /// Filled in for `.factoryPack` (and for a missing pack).
    public var packName = ""
    /// From disk; 0 if it was not found or could not be counted.
    public var size: Int64 = 0
    /// .amxd (MxPatchRef) rather than a sample.
    public var isDevice = false
    /// FileRef numbers in document order — a patcher addresses by them.
    public var refIndexes: [Int] = []

    public init(ref: FileRefInfo, resolved: ResolvedRef) {
        self.ref = ref
        self.resolved = resolved
    }

    public var path: String { resolved.resolvedPath }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Which media files a set needs and where they come from. It reads nothing from disk beyond what
/// `AlsFile` has already read, and writes nothing.
public enum SampleScan {
    /// `setDir` is the .als folder itself, not the project folder. `ProjectIndex` counts it the
    /// same way, and these two must not diverge: otherwise "in the project" here and "lost" in the
    /// catalog would be talking about different things.
    public static func of(_ info: AlsInfo?, setDir: String, env: LiveEnvironment,
                          probe: ProbeCache = ProbeCache()) -> [SampleDep] {
        guard let info else { return [] }
        var list: [SampleDep] = []

        // Two levels of folding. First by the reference itself: identical references resolve
        // identically, and there is no point calling RefResolver 28 thousand times. Then by the
        // path found: different references (one through a pack, another by absolute path) lead
        // to one file, and it has to be copied once.
        var byRaw: [String: Int?] = [:]        // nil — a blank, remembered so it is not resolved again
        var byFile: [String: Int] = [:]

        for (i, fr) in info.files.enumerated() {
            let device = fr.container == "MxPatchRef"
            guard fr.isSampleDependency || device else { continue }

            let raw = "\(fr.relativePathType)|\(fr.relativePath)|\(fr.absolutePath)|\(fr.livePackName)"
            if let known = byRaw[raw] {
                if let n = known { list[n].refIndexes.append(i) }
                continue
            }

            let rr = RefResolver.resolve(fr, projectDir: setDir, env: env, probe: probe)
            if rr.status == .empty {
                byRaw[raw] = .some(nil)
                continue
            }

            let fileKey = rr.status == .found
                ? rr.resolvedPath.lowercased()
                : "?" + (fr.relativePath.isEmpty ? fr.absolutePath : fr.relativePath)

            if let n = byFile[fileKey] {
                list[n].refIndexes.append(i)
                byRaw[raw] = .some(n)
                continue
            }

            var dep = SampleDep(ref: fr, resolved: rr)
            dep.isDevice = device
            dep.refIndexes = [i]
            (dep.origin, dep.packName) = classify(rr, fr, setDir: setDir, env: env)
            dep.size = dep.origin == .missing ? 0 : sizeOf(rr.resolvedPath)

            list.append(dep)
            byRaw[raw] = .some(list.count - 1)
            byFile[fileKey] = list.count - 1
        }
        return list
    }

    /// The order of the checks matters. "In the project" comes first: a project lying inside the
    /// User Library is still one's own project, and its samples are not "from the library".
    static func classify(_ rr: ResolvedRef, _ fr: FileRefInfo, setDir: String,
                         env: LiveEnvironment) -> (SampleOrigin, String) {
        if rr.status != .found {
            return (.missing, rr.status == .missingPack ? fr.livePackName : "")
        }
        let p = rr.resolvedPath

        if under(p, setDir) { return (.inProject, "") }

        if fr.relativePathType == 5 && !fr.livePackName.isEmpty { return (.factoryPack, fr.livePackName) }

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

    /// Whether a path lies inside a root. Compared as full paths, or ".../Samples2" would pass for
    /// ".../Samples".
    static func under(_ path: String, _ root: String) -> Bool {
        guard !path.isEmpty, !root.isEmpty else { return false }
        return SampleIndex.inside(path, root)
    }

    /// By the same rule as `SetEntry.projectDir`: no more than four levels up.
    static func inSomeProject(_ path: String) -> Bool {
        var d = (path as NSString).deletingLastPathComponent
        for _ in 0..<4 {
            guard !d.isEmpty, d != "/" else { return false }
            if (d as NSString).lastPathComponent.lowercased().hasSuffix(" project") { return true }
            d = (d as NSString).deletingLastPathComponent
        }
        return false
    }

    /// .adg and .amxd are sometimes folders — their size is the sum of the files inside, not 0. A 0
    /// on a dependency that was found (origin != missing) would otherwise be indistinguishable
    /// from "not found".
    static func sizeOf(_ path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return FileStat.size(of: path)
        }
        return dirSize(path, depth: 0)
    }

    /// The recursive sum of file sizes in a folder, walked by hand: an unreadable subfolder only
    /// cuts the count short for itself. The depth limit is the same number RenderIndex uses;
    /// without it a mounted loop inflates the sum, since a repeat visit cannot be told from a new
    /// one but by depth.
    static func dirSize(_ dir: String, depth: Int) -> Int64 {
        guard depth <= 4, let entries = FolderScan.list(dir) else { return 0 }
        var total: Int64 = 0
        for e in entries {
            total += e.isDirectory ? dirSize(FolderScan.combine(dir, e.name), depth: depth + 1) : e.size
        }
        return total
    }
}
