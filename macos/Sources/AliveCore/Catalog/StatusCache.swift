// Mac-only: status.cache — the facts the catalog keeps beside index.cache (whose layout is
// upstream's v11 and must not change): which references of a set live on an unmounted volume,
// when its newest render was made, and what the walk of each project folder found (weight,
// render names, which sets have Backup copies). JSON, written only when it changed.
import Foundation

/// What a scan learned about one set beyond upstream's fields. Valid only while the set's size
/// and modification time are the ones recorded (the same stamp index.cache uses).
public struct SetFacts: Equatable, Sendable, Codable {
    public var size: Int64
    public var modifiedTicks: Int64
    /// Resolved paths of the references that were unresolved because their volume was not mounted.
    public var offline: [String]
    /// Modification date of the newest render of the set's project, UTC ticks.
    public var newestRenderTicks: Int64?

    public init(size: Int64, modifiedTicks: Int64, offline: [String] = [], newestRenderTicks: Int64? = nil) {
        self.size = size
        self.modifiedTicks = modifiedTicks
        self.offline = offline
        self.newestRenderTicks = newestRenderTicks
    }

    public func matches(_ entry: SetEntry) -> Bool {
        size == entry.size && DotNetTicks.sameInstant(DotNetTicks.date(utc: modifiedTicks), entry.modified)
    }

    public var newestRender: Date? { newestRenderTicks.map { DotNetTicks.date(utc: $0) } }
}

/// What the last walk of one project folder found; lets a scan skip the walk when nothing in the
/// folder changed.
public struct ProjectFacts: Equatable, Sendable, Codable {
    public var bytes: Int64
    public var files: Int
    /// Names of the renders (the order `RenderScan.finish` gave them).
    public var renders: [String]
    public var newestRenderTicks: Int64?
    /// Lowercased names of the sets that have copies in Backup. The save times themselves live in
    /// activity.cache; this only keeps `Activity.build` from counting the .als time of such a set.
    public var saveSets: [String]

    public init(bytes: Int64 = 0, files: Int = 0, renders: [String] = [], newestRenderTicks: Int64? = nil,
                saveSets: [String] = []) {
        self.bytes = bytes
        self.files = files
        self.renders = renders
        self.newestRenderTicks = newestRenderTicks
        self.saveSets = saveSets
    }
}

public struct StatusCacheContent: Equatable, Sendable, Codable {
    public static let version = 1
    public var version = StatusCacheContent.version
    /// Keyed by lowercased set path.
    public var sets: [String: SetFacts] = [:]
    /// Keyed by lowercased project folder.
    public var projects: [String: ProjectFacts] = [:]

    public init() {}
}

public enum StatusCache {
    public static func path(dir: String) -> String { AppHome.file("status.cache", in: dir) }

    /// Missing, damaged or foreign-version files read as empty: the facts are rebuilt by a scan.
    public static func load(dir: String) -> StatusCacheContent {
        guard let data = FileManager.default.contents(atPath: path(dir: dir)) else { return StatusCacheContent() }
        do {
            let content = try JSONDecoder().decode(StatusCacheContent.self, from: data)
            return content.version == StatusCacheContent.version ? content : StatusCacheContent()
        } catch {
            Diag.warn("status.cache unreadable, rebuilding: \(error)")
            return StatusCacheContent()
        }
    }

    /// Writes only when the content differs from what is on disk (a no-op rescan leaves the
    /// file's mtime alone). Returns whether the file now holds `content` (written or already so);
    /// false: the write failed.
    @discardableResult
    public static func save(_ content: StatusCacheContent, dir: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            _ = try AppHome.writeAtomicallyIfChanged(try encoder.encode(content), to: path(dir: dir))
            return true
        } catch {
            Diag.fail("status.cache write", error)
            return false
        }
    }
}
