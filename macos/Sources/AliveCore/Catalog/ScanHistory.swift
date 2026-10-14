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

    public init(path: String, eventId: UInt64, deviceUUID: String, isLocal: Bool, fullWalkAt: Date) {
        self.path = path
        self.eventId = eventId
        self.deviceUUID = deviceUUID
        self.isLocal = isLocal
        self.fullWalkAt = fullWalkAt
    }
}

/// The volume a root lives on, as far as the journal is concerned.
public struct RootIdentity: Equatable, Sendable {
    /// nil: the volume has no journal (FSEvents cannot replay it).
    public var deviceUUID: String?
    public var isLocal: Bool

    public init(deviceUUID: String?, isLocal: Bool) {
        self.deviceUUID = deviceUUID
        self.isLocal = isLocal
    }

    public static func of(_ path: String) -> RootIdentity {
        let local = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsLocalKey]))?
            .volumeIsLocal ?? false
        var st = stat()
        guard stat(path, &st) == 0,
              let uuid = FSEventsCopyUUIDForDevice(st.st_dev),
              let text = CFUUIDCreateString(nil, uuid) as String? else {
            return RootIdentity(deviceUUID: nil, isLocal: local)
        }
        return RootIdentity(deviceUUID: text, isLocal: local)
    }
}

public enum ScanHistory {
    public static func path(dir: String) -> String { AppHome.file("scan-history.cfg", in: dir) }

    /// Keyed by lowercased root path. A missing or damaged file reads as empty (every root then
    /// gets a full scan, which is always correct).
    public static func load(dir: String) -> [String: RootHistory] {
        guard let lines = AppHome.readLines(path(dir: dir)) else { return [:] }
        var out: [String: RootHistory] = [:]
        for line in lines {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5, let id = UInt64(f[1]), let ticks = Int64(f[4]),
                  DotNetTicks.isValid(ticks: ticks), !f[0].isEmpty else { continue }
            out[f[0].lowercased()] = RootHistory(path: f[0], eventId: id, deviceUUID: f[2], isLocal: f[3] == "1",
                                                 fullWalkAt: DotNetTicks.date(utc: ticks))
        }
        return out
    }

    /// Written only when it changed.
    public static func save(_ history: [String: RootHistory], dir: String) {
        let lines = history.values.sorted { $0.path < $1.path }.map {
            [$0.path, String($0.eventId), $0.deviceUUID, $0.isLocal ? "1" : "0",
             String(DotNetTicks.utc($0.fullWalkAt))].joined(separator: "\t")
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        do { try AppHome.writeAtomicallyIfChanged(Data(text.utf8), to: path(dir: dir)) } catch {
            Diag.fail("scan-history.cfg write", error)
        }
    }
}
