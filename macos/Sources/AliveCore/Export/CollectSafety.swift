// Mac-only: what Collect All may copy. Upstream trusts the paths in a set; a set that came
// from somebody else is an untrusted document, and "collect" is a copy operation driven by it.
import Foundation

/// Why a file a set refers to is not collected. The reference stays as it was in the original.
public enum CollectRefusal: Sendable, Equatable {
    /// Not a media or Live file (by extension): `id_rsa`, `.env`, a text file, a database.
    case notMedia
    /// A folder that is not a known Live bundle (.adg, .amxd, …), a device node, a socket.
    case notRegularFile
    /// Inside a hidden (dot) folder outside the project: `~/.ssh`, `~/.aws`, `~/.config`.
    case hiddenFolder
    /// Inside a place that holds credentials or private data (Keychains, Mail, browsers…).
    case sensitiveLocation
}

public enum CollectSafety {
    /// Audio, video and MIDI that Live takes into a set as samples or clips.
    public static let mediaExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "flac", "ogg", "oga", "opus", "mp3", "mp2", "m4a", "m4b",
        "mp4", "m4v", "mov", "aac", "caf", "wma", "ac3", "au", "snd", "w64", "rf64", "rx2", "rex",
        "mid", "midi", "syx", "asd",
    ]

    /// Live devices and racks, and the analysis / clip files next to samples. `.adg`, `.adv`,
    /// `.amxd`, `.alc` may be folders (bundles).
    public static let liveExtensions: Set<String> = ["adg", "adv", "amxd", "alc", "agr", "ams"]

    /// Only these may be copied when they are folders.
    public static let bundleExtensions: Set<String> = ["adg", "adv", "amxd", "alc"]

    /// Places under the user's home that hold private data. The hidden-folder rule already
    /// covers `~/.ssh`, `~/.gnupg`, `~/.aws` …; these are the visible ones.
    static let sensitiveHomeFolders = [
        "Library/Keychains", "Library/Cookies", "Library/Mail", "Library/Messages", "Library/Safari",
        "Library/Application Support/AddressBook", "Library/Application Support/MobileSync",
        "Library/Application Support/Google/Chrome", "Library/Application Support/Firefox",
        "Library/Application Support/com.apple.TCC", "Library/Group Containers",
    ]

    /// Whether `realPath` (symlinks already resolved) may be collected.
    ///
    /// `projectRoot` is set for files that lie inside the set's own project: those are the
    /// person's own material, whatever their extension, and only the folder-vs-file rule
    /// applies, plus "no hidden folder below the project". Everything else has to look like
    /// media or a Live device, live outside hidden and private folders, and be a plain file.
    public static func refusal(forRealPath realPath: String, projectRoot: String? = nil,
                               home: String = NSHomeDirectory()) -> CollectRefusal? {
        var st = stat()
        guard stat(realPath, &st) == 0 else { return nil }          // a missing file is another matter
        let ext = (realPath as NSString).pathExtension.lowercased()

        if isSensitive(realPath, home: home) { return .sensitiveLocation }
        if hasHiddenComponent(realPath, below: projectRoot) { return .hiddenFolder }

        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            return bundleExtensions.contains(ext) ? nil : .notRegularFile
        case S_IFREG:
            if projectRoot != nil { return nil }
            return mediaExtensions.contains(ext) || liveExtensions.contains(ext) ? nil : .notMedia
        default:
            return .notRegularFile
        }
    }

    static func isSensitive(_ path: String, home: String) -> Bool {
        let p = path.lowercased()
        let h = home.hasSuffix("/") ? home : home + "/"
        for rel in sensitiveHomeFolders {
            let root = (h + rel).lowercased()
            if p == root || p.hasPrefix(root + "/") { return true }
        }
        return false
    }

    /// Any path component starting with a dot, counted below `root` when given (a project that
    /// itself lies in a hidden folder is still the person's project).
    static func hasHiddenComponent(_ path: String, below root: String?) -> Bool {
        var rest = path
        if let root, let rel = CollectScan.relative(root: root, path: path) { rest = rel }
        return rest.split(separator: "/").contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
    }

    /// `realpath(3)`; nil when the path cannot be resolved (missing, loop).
    public static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
