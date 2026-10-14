// Mac-only: is a path on a volume that isn't connected right now? A file under
// `/Volumes/<name>/…` whose volume isn't mounted is *offline*, not missing. Paths on the boot
// volume are never offline.
import Foundation

public enum VolumeState {
    /// The volume name a path lives on (`/Volumes/LaCie RAID 8TB/x.wav` → "LaCie RAID 8TB"),
    /// or nil for paths on the boot volume. Accepts `/private/Volumes/…` too.
    public static func volumeName(of path: String) -> String? {
        var p = path
        if p.hasPrefix("/private/") { p.removeFirst("/private".count) }
        guard p.hasPrefix("/Volumes/") else { return nil }
        let rest = p.dropFirst("/Volumes/".count)
        guard let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first,
              !name.isEmpty else { return nil }
        return String(name)
    }

    /// Names of the volumes mounted under `/Volumes` right now.
    public static func mountedVolumeNames(fileManager: FileManager = .default) -> Set<String> {
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                 options: [.skipHiddenVolumes]) ?? []
        return Set(urls.compactMap { volumeName(of: $0.path) })
    }

    /// Whether `path` is on a volume that isn't mounted. `mounted` is injectable for tests and
    /// so a caller checking many paths reads the mount table once.
    public static func isOffline(_ path: String, mounted: Set<String>) -> Bool {
        guard let name = volumeName(of: path) else { return false }
        return !mounted.contains(name)
    }
}
