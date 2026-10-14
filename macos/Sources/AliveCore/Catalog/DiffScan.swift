// Mac-only: the startup "diff scan". Instead of walking every folder of a root at launch, ask the
// file system's event journal (FSEvents) what changed since the last scan began, and re-read only
// the project folders where something did. Everything that decides *whether* that is safe lives
// here as pure functions; the actual replay is in FSEventsReplay.swift.
import CoreServices
import Foundation

/// Why a root is walked in full instead of being diffed.
public enum FullScanReason: Equatable, Sendable {
    case noHistory
    case noCachedSets
    case deviceChanged
    /// Network volumes (SMB, NFS…) are not covered by the journal.
    case notLocal
    case noJournal
    /// The last full walk is old enough that a forgotten gap in the journal is plausible.
    case tooOld
    case rootUnreadable
    /// The journal could not be replayed (timeout, stream refused).
    case replayFailed
    /// `MustScanSubDirs`, `RootChanged`, `UserDropped`, `KernelDropped`, id wrap, mount/unmount:
    /// the journal itself says it cannot be trusted for this range.
    case journalUnreliable
    /// Too much changed for a partial scan to be worth it.
    case tooManyChanges
    /// Something changed directly in the root (above the project level).
    case changedAtRoot
}

public enum RootScanMode: Equatable, Sendable {
    case full(FullScanReason)
    /// Replay the journal from this event id.
    case replay(since: UInt64)
}

/// What the replayed events ask of the scan.
public enum DiffPlan: Equatable, Sendable {
    /// Read these directories again (project folders or new ground); everything else is reused.
    case regions([String])
    case full(FullScanReason)
}

public struct ReplayedEvent: Equatable, Sendable {
    public var path: String
    public var flags: UInt32
    public init(path: String, flags: UInt32) {
        self.path = path
        self.flags = flags
    }
}

public enum ReplayOutcome: Equatable, Sendable {
    case events([ReplayedEvent])
    case unusable(FullScanReason)
}

/// The three things the diff scan asks the system, injectable so tests need no real journal.
public struct ScanHistoryOps: Sendable {
    public var identity: @Sendable (_ root: String) -> RootIdentity
    public var replay: @Sendable (_ root: String, _ since: UInt64) -> ReplayOutcome
    public var currentEventId: @Sendable () -> UInt64

    public init(identity: @escaping @Sendable (String) -> RootIdentity,
                replay: @escaping @Sendable (String, UInt64) -> ReplayOutcome,
                currentEventId: @escaping @Sendable () -> UInt64) {
        self.identity = identity
        self.replay = replay
        self.currentEventId = currentEventId
    }

    public static let live = ScanHistoryOps(
        identity: { RootIdentity.of($0) },
        replay: { FSEventsReplay.events(root: $0, since: $1) },
        currentEventId: { FSEventsGetCurrentEventId() })
}

public enum DiffScan {
    /// A root not walked in full for this long is walked in full: the journal is a convenience,
    /// not a guarantee, and a week bounds how long a missed change can linger.
    public static let maxHistoryAge: TimeInterval = 7 * 24 * 3600
    public static let maxRegions = 400

    /// Full walk or journal replay for one root? Pure.
    public static func mode(history: RootHistory?, identity: RootIdentity, hasCachedSets: Bool,
                            now: Date = Date()) -> RootScanMode {
        guard let history else { return .full(.noHistory) }
        guard identity.isLocal, history.isLocal else { return .full(.notLocal) }
        guard let uuid = identity.deviceUUID, !uuid.isEmpty else { return .full(.noJournal) }
        guard uuid == history.deviceUUID else { return .full(.deviceChanged) }
        guard hasCachedSets else { return .full(.noCachedSets) }
        guard now.timeIntervalSince(history.fullWalkAt) <= maxHistoryAge else { return .full(.tooOld) }
        return .replay(since: history.eventId)
    }

    /// Flags after which the journal's picture of the range is incomplete.
    static let unreliable = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
        | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)

    /// What an outcome means for the scan. `root` is the path as the catalog knows it (event
    /// paths are already rebased onto it); `projectDirs` are the known project folders, lowercased.
    public static func plan(for outcome: ReplayOutcome, root: String, projectDirs: Set<String>) -> DiffPlan {
        let events: [ReplayedEvent]
        switch outcome {
        case .unusable(let why): return .full(why)
        case .events(let list): events = list
        }
        let top = norm(root)
        var found = Set<String>()
        for e in events {
            if e.flags & unreliable != 0 { return .full(.journalUnreliable) }
            if e.flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
            guard let region = region(of: e, root: top, projectDirs: projectDirs) else { continue }
            if region.lowercased() == top.lowercased() { return .full(.changedAtRoot) }
            found.insert(region)
        }
        let merged = dropNested(found)
        return merged.count > maxRegions ? .full(.tooManyChanges) : .regions(merged.sorted())
    }

    /// The directory an event makes us read again. nil: nothing the catalog shows.
    static func region(of e: ReplayedEvent, root: String, projectDirs: Set<String>) -> String? {
        let path = norm(e.path)
        let low = path.lowercased(), rootLow = root.lowercased()
        guard low == rootLow || low.hasPrefix(rootLow + "/") else { return nil }
        if low == rootLow {
            // Things that happen to the root itself (attributes, an xattr, its own creation long
            // ago) say nothing about its contents; losing it does.
            let lost = UInt32(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
            return e.flags & lost != 0 ? root : nil
        }
        // Hidden entries (.DS_Store, ._AppleDouble) and the rescue helper's probes are not scanned.
        let relative = String(path.dropFirst(root.count))
        if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return nil }
        if low.hasSuffix(FolderScan.probeSuffix) { return nil }

        // Inside a project we already know: that project is read again.
        var cursor = path
        while cursor.count > root.count {
            if projectDirs.contains(cursor.lowercased()) { return cursor }
            cursor = (cursor as NSString).deletingLastPathComponent
        }
        // New ground: the directory itself when it is one, else the folder holding the file.
        let isDir = e.flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
        let dir = isDir ? path : (path as NSString).deletingLastPathComponent
        // A set sits at most three folders below its "* Project" folder.
        if let project = SetEntry.projectFolder(ofSetAt: dir + "/_.als")?.folder,
           project.lowercased().hasPrefix(rootLow + "/") { return project }
        return dir
    }

    /// Regions lying inside another region are covered by it.
    static func dropNested(_ regions: Set<String>) -> [String] {
        var kept: [String] = []
        for r in regions.sorted(by: { $0.count < $1.count }) {
            let low = r.lowercased() + "/"
            if kept.contains(where: { low.hasPrefix($0.lowercased() + "/") }) { continue }
            kept.append(r)
        }
        return kept
    }

    /// May a project folder keep what the last walk found? True when no region touches it:
    /// it is neither inside a region nor holds one.
    public static func isClean(projectDir: String, regions: [String]) -> Bool {
        let p = projectDir.lowercased()
        for r in regions {
            let low = r.lowercased()
            if p == low || p.hasPrefix(low + "/") || low.hasPrefix(p + "/") { return false }
        }
        return true
    }

    static func norm(_ p: String) -> String {
        var s = (p as NSString).standardizingPath
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
