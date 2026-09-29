// Port of src/RefResolver.cs (POSIX paths; the probe cache is an instance instead of a static)
import Foundation

public enum RefStatus: Sendable {
    /// No reference: an empty FileRef placeholder, and most of a set is these.
    case empty
    /// The file is where it should be.
    case found
    /// Not found — a real loss.
    case missing
    /// The Live Pack the set refers to was not found.
    case missingPack
}

public struct ResolvedRef: Sendable {
    public var ref: FileRefInfo
    public var status: RefStatus = .empty
    public var resolvedPath = ""
    /// For `.missingPack`: the pack name.
    public var note = ""

    public init(ref: FileRefInfo) { self.ref = ref }
}

/// Cache of "does this file exist" probes for the duration of ONE scan.
///
/// Measured on a real library: twenty sets hold 29,643 sample references and only 1,112 distinct
/// paths — 96% of the checks ask for what has already been asked. What is cached is the result
/// of the probe, not the reference. It must not outlive a scan: files change without asking, and
/// "rescan" has to mean "check again".
public final class ProbeCache: @unchecked Sendable {
    private var map: [String: Bool] = [:]
    private let lock = NSLock()
    public init() {}

    func exists(_ path: String) -> Bool {
        let key = path.lowercased()      // default macOS volumes are case-insensitive
        lock.lock()
        if let hit = map[key] { lock.unlock(); return hit }
        lock.unlock()
        let ok = FileManager.default.fileExists(atPath: path)   // files and folders: .adg/.amxd may be folders
        lock.lock(); map[key] = ok; lock.unlock()
        return ok
    }
}

/// `RelativePathType` in the .als names the ROOT that `RelativePath` is measured from:
///   0 - no relative root, the absolute path only
///   1 - from the project folder, may go upwards (../../Samples/...)
///   3 - inside the project folder
///   5 - from a Live Pack root, the pack name in LivePackName
///   6 - from the User Library
///   7 - from the Builtin resources of the installed Live
/// The absolute path is only the last hint: in other people's and older projects it leads to
/// another machine, another drive, or a previous Live version.
public enum RefResolver {
    public static func resolve(_ fr: FileRefInfo, projectDir: String, env: LiveEnvironment,
                               probe: ProbeCache = ProbeCache()) -> ResolvedRef {
        var res = ResolvedRef(ref: fr)
        let noRel = fr.relativePath.isEmpty, noAbs = fr.absolutePath.isEmpty
        if noRel && noAbs { res.status = .empty; return res }

        // Sets made on Windows may carry backslashes.
        let rel: String? = noRel ? nil : fr.relativePath.replacingOccurrences(of: "\\", with: "/")

        switch fr.relativePathType {
        case 1, 3:
            if attempt(projectDir, rel, &res, probe) { return res }
        case 5:
            let packRoot = fr.livePackName.isEmpty ? nil : env.packRoot(named: fr.livePackName)
            if attempt(packRoot, rel, &res, probe) { return res }
            // The pack is not installed at all — a different trouble from a lost sample.
            if packRoot == nil, !fr.livePackName.isEmpty, !exists(fr.absolutePath, probe) {
                res.status = .missingPack
                res.note = fr.livePackName
                res.resolvedPath = fr.relativePath
                return res
            }
        case 6:
            if attempt(env.userLibrary, rel, &res, probe) { return res }
        case 7:
            if attempt(env.builtin, rel, &res, probe) { return res }
            if attempt(env.coreLibrary, rel, &res, probe) { return res }
        default: break
        }

        // Fallbacks: the absolute path, then the other roots.
        if exists(fr.absolutePath, probe) {
            res.status = .found
            res.resolvedPath = fr.absolutePath
            return res
        }
        for root in [projectDir, env.userLibrary, env.builtin, env.coreLibrary]
        where attempt(root, rel, &res, probe) { return res }

        res.status = .missing
        res.resolvedPath = noAbs ? fr.relativePath : fr.absolutePath
        return res
    }

    private static func attempt(_ root: String?, _ relative: String?, _ res: inout ResolvedRef,
                                _ probe: ProbeCache) -> Bool {
        guard let root, !root.isEmpty, let relative, !relative.isEmpty else { return false }
        let full = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(relative).standardized.path
        guard probe.exists(full) else { return false }
        res.status = .found
        res.resolvedPath = full
        return true
    }

    private static func exists(_ path: String, _ probe: ProbeCache) -> Bool {
        !path.isEmpty && probe.exists(path)
    }
}
