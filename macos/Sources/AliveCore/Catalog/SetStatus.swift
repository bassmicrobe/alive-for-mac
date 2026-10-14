// Mac-only: per-set facts upstream doesn't track — files on volumes that aren't connected,
// whether the set opens as saved, and whether its render is older than the set. Kept out of
// index.cache (upstream layout v11); persisted in a sidecar by ProjectIndex.
import Foundation

/// Can the set be opened as it was saved, and if not, why. Order of precedence when several
/// apply: missing files, missing plugins, offline volume, unknown, ready.
public enum Readiness: String, Sendable, CaseIterable {
    /// The .als could not be read (damaged, wrong format, no permission): nothing about it is
    /// known, so it must never count as ready. Takes precedence over everything else.
    case unreadable
    /// Every referenced file found and every plugin installed.
    case ready
    /// Nothing known to be missing, but some files live on a volume that isn't connected.
    case offline
    /// Some referenced files are gone (not merely offline).
    case missingFiles
    /// Some plugins aren't installed.
    case missingPlugins
    /// Files are fine but the installed-plugin list is unavailable (PORTING rule 11: unknown,
    /// never "not ready").
    case unknown
}

public struct SetStatus: Equatable, Sendable {
    /// Referenced files under `/Volumes/<name>` whose volume isn't mounted.
    public var offlineFiles: Int
    /// Names of the unmounted volumes those files live on, sorted.
    public var offlineVolumes: [String]
    /// Referenced files that are really gone (`SetEntry.missingFiles` minus `offlineFiles`).
    public var missingFiles: Int
    /// Plugins not installed; `nil` when the inventory is unavailable.
    public var missingPlugins: Int?
    /// The set failed to parse (`SetEntry.error` is not empty); see `Readiness.unreadable`.
    public var isUnreadable: Bool
    /// Modification date of the newest render next to the set, if any.
    public var newestRender: Date?
    /// The set was saved after its newest render (beyond `staleTolerance`).
    public var renderIsStale: Bool

    /// Saving a set a moment after exporting is normal; only flag real gaps.
    public static let staleTolerance: TimeInterval = 120

    public init(offlineFiles: Int = 0, offlineVolumes: [String] = [], missingFiles: Int = 0,
                missingPlugins: Int? = 0, newestRender: Date? = nil, renderIsStale: Bool = false,
                isUnreadable: Bool = false) {
        self.isUnreadable = isUnreadable
        self.offlineFiles = offlineFiles
        self.offlineVolumes = offlineVolumes
        self.missingFiles = missingFiles
        self.missingPlugins = missingPlugins
        self.newestRender = newestRender
        self.renderIsStale = renderIsStale
    }

    public var readiness: Readiness {
        if isUnreadable { return .unreadable }
        if missingFiles > 0 { return .missingFiles }
        if let plugins = missingPlugins, plugins > 0 { return .missingPlugins }
        if offlineFiles > 0 { return .offline }
        if missingPlugins == nil { return .unknown }
        return .ready
    }

    /// Whether a render saved at `render` is older than the set saved at `setModified`.
    public static func isStale(setModified: Date, newestRender render: Date?) -> Bool {
        guard let render else { return false }
        return setModified.timeIntervalSince(render) > staleTolerance
    }

    /// The status implied by the upstream fields alone (no offline/volume knowledge, no render
    /// dates). Placeholder until the sidecar facts are available, and the fallback for sets the
    /// sidecar doesn't cover.
    public static func basic(_ entry: SetEntry, pluginsKnown: Bool) -> SetStatus {
        SetStatus(missingFiles: entry.missingFiles,
                  missingPlugins: pluginsKnown ? entry.missingPlugins : nil,
                  isUnreadable: !entry.error.isEmpty)
    }

    /// The one place a set's status is worked out (scan, mount/unmount handling and tests all use
    /// it). `offlinePaths` are the references recorded as unresolved because their volume was not
    /// mounted when the set was parsed; upstream counts them in `entry.missingFiles`, so they come
    /// off that number. Found samples (`entry.samples`) that sit on a volume which is unmounted
    /// *now* are offline too — that is how an unplugged drive shows without a rescan.
    public static func derive(entry: SetEntry, offlinePaths: [String], newestRender: Date?,
                              mounted: Set<String>, pluginsKnown: Bool) -> SetStatus {
        if !entry.error.isEmpty {
            // A set that did not parse says nothing about its files or plugins.
            return SetStatus(missingPlugins: pluginsKnown ? 0 : nil, newestRender: newestRender,
                             renderIsStale: isStale(setModified: entry.modified, newestRender: newestRender),
                             isUnreadable: true)
        }
        var volumes = Set<String>()
        var offline = 0
        for path in entry.samples + offlinePaths {
            guard let name = VolumeState.volumeName(of: path), !mounted.contains(name) else { continue }
            offline += 1
            volumes.insert(name)
        }
        return SetStatus(offlineFiles: offline, offlineVolumes: volumes.sorted(),
                         missingFiles: max(0, entry.missingFiles - offlinePaths.count),
                         missingPlugins: pluginsKnown ? entry.missingPlugins : nil,
                         newestRender: newestRender,
                         renderIsStale: isStale(setModified: entry.modified, newestRender: newestRender))
    }
}
