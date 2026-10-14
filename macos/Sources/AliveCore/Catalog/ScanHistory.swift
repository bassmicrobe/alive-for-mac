// Mac-only: scan-history.cfg — per catalog root, where the file system's event journal stood when
// the last scan began, so the next launch can ask FSEvents "what changed since" instead of walking
// the whole tree. One line per root: path, event id, device UUID, local flag, time of the last
// full walk (UTC ticks), tab separated.
import CoreServices
import Foundation

/// What the journal knew about one root at the end of a scan.
public struct RootHistory: Equatable, Sendable {
    public var path: String
    /// `FSEventsGetCurrentEventId()` taken *before* the scan walked anything, so changes made
    /// during the scan are replayed next time rather than lost.
    public var eventId: UInt64
    /// `FSEventsCopyUUIDForDevice`: changes when the volume's journal is not the same one.
    public var deviceUUID: String
    public var isLocal: Bool
    /// The last time this root was walked in full (a diff scan keeps the old value).
    public var fullWalkAt: Date
    /// Stamp of `index.cache` + `status.cache` as they were when this checkpoint was written
    /// (`ScanHistory.catalogStamp`). The checkpoint is only good for the catalog it was taken
    /// with: a different (older, newer, half-written) pair forces a full walk.
    public var catalogStamp: String

    public init(path: String, eventId: UInt64, deviceUUID: String, isLocal: Bool, fullWalkAt: Date,
                catalogStamp: String = "") {
        self.path = path
        self.eventId = eventId
        self.deviceUUID = deviceUUID
        self.isLocal = isLocal
        self.fullWalkAt = fullWalkAt
        self.catalogStamp = catalogStamp
    }
}

/// The volume a root lives on, as far as the journal is concerned.
public struct RootIdentity: Equatable, Sendable {
    /// nil: the volume has no journal (FSEvents cannot replay it).
    public var deviceUUID: String?
    public var isLocal: Bool
    /// A fixed internal volume (the boot disk or another internal one). Event ids are host-global,
    /// so a journal position is only meaningful for a volume that never leaves this Mac: a
    /// removable or external drive may have been written on another Mac, whose ids are unrelated.
    public var isInternal: Bool

    public init(deviceUUID: String?, isLocal: Bool, isInternal: Bool = true) {
        self.deviceUUID = deviceUUID
        self.isLocal = isLocal
        self.isInternal = isInternal
    }

    public static func of(_ path: String) -> RootIdentity {
        let values = try? URL(fileURLWithPath: path).resourceValues(
            forKeys: [.volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey])
        let local = values?.volumeIsLocal ?? false
        let internalVolume = values?.volumeIsInternal == true && values?.volumeIsRemovable != true
            && values?.volumeIsEjectable != true
        var st = stat()
        guard stat(path, &st) == 0,
              let uuid = FSEventsCopyUUIDForDevice(st.st_dev),
              let text = CFUUIDCreateString(nil, uuid) as String? else {
            return RootIdentity(deviceUUID: nil, isLocal: local, isInternal: internalVolume)
        }
        return RootIdentity(deviceUUID: text, isLocal: local, isInternal: internalVolume)
    }
}

public enum ScanHistory {
    public static func path(dir: String) -> String { AppHome.file("scan-history.cfg", in: dir) }

    /// Identifies the on-disk catalog (`index.cache` and `status.cache`: size and modification
    /// time of each). Taken after both were saved, and compared before a journal replay is trusted.
    public static func catalogStamp(dir: String) -> String {
        func part(_ path: String) -> String {
            guard let st = FileStat.of(path) else { return "-" }
            return "\(st.size).\(Int64((st.modified.timeIntervalSince1970 * 1_000_000).rounded()))"
        }
        return part(IndexCache.path(dir: dir)) + "|" + part(StatusCache.path(dir: dir))
    }

    /// Keyed by lowercased root path. A missing or damaged file reads as empty (every root then
    /// gets a full scan, which is always correct).
    public static func load(dir: String) -> [String: RootHistory] {
        guard let lines = AppHome.readLines(path(dir: dir)) else { return [:] }
        var out: [String: RootHistory] = [:]
        for line in lines {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // Five fields: a file from before the catalog stamp existed (stamp "" never matches).
            guard f.count == 5 || f.count == 6, let id = UInt64(f[1]), let ticks = Int64(f[4]),
                  DotNetTicks.isValid(ticks: ticks), !f[0].isEmpty else { continue }
            out[f[0].lowercased()] = RootHistory(path: f[0], eventId: id, deviceUUID: f[2], isLocal: f[3] == "1",
                                                 fullWalkAt: DotNetTicks.date(utc: ticks),
                                                 catalogStamp: f.count == 6 ? f[5] : "")
        }
        return out
    }

    /// Written only when it changed.
    public static func save(_ history: [String: RootHistory], dir: String) {
        let lines = history.values.sorted { $0.path < $1.path }.map {
            [$0.path, String($0.eventId), $0.deviceUUID, $0.isLocal ? "1" : "0",
             String(DotNetTicks.utc($0.fullWalkAt)), $0.catalogStamp].joined(separator: "\t")
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        do { try AppHome.writeAtomicallyIfChanged(Data(text.utf8), to: path(dir: dir)) } catch {
            Diag.fail("scan-history.cfg write", error)
        }
    }
}
