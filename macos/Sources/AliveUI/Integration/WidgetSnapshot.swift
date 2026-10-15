// Mac-only: writes widget.json (the desktop widget's data, see AliveCore.WidgetSnapshot) next to the
// app's other data and asks WidgetKit to redraw. The widget only finds it in the default data
// folder; with a custom ALIVE_HOME it keeps showing its placeholder.
import AliveCore
import Foundation
import WidgetKit

enum WidgetSnapshotWriter {
    enum Outcome: Equatable {
        case written
        case unchanged
        case failed(String)
    }

    /// Writes the snapshot unless the file already holds the same picture of the work. Pure disk work,
    /// no WidgetKit: tests call this directly.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, dir: String) -> Outcome {
        let path = WidgetSnapshot.appFileURL(dataDir: dir).path
        removeLegacyFile(dir: dir)
        if let existing = WidgetSnapshot.load(from: URL(fileURLWithPath: path)), existing.sameContent(as: snapshot) {
            return .unchanged
        }
        do {
            try AppHome.writeAtomically(try snapshot.encoded(), to: path)
            return .written
        } catch {
            Diag.fail("widget.json write", error)
            return .failed(error.localizedDescription)
        }
    }

    /// Earlier builds wrote widget.json straight into the data folder; the widget no longer reads it there.
    private static func removeLegacyFile(dir: String) {
        let legacy = AppHome.file(WidgetSnapshot.fileName, in: dir)
        if FileManager.default.fileExists(atPath: legacy) { try? FileManager.default.removeItem(atPath: legacy) }
    }

    /// A custom ALIVE_HOME is invisible to the widget: nothing to reload then.
    private static var usesDefaultFolder: Bool {
        ProcessInfo.processInfo.environment["ALIVE_HOME"]?.isEmpty ?? true
    }

    static func reloadTimelines() {
        if usesDefaultFolder { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// One publisher per app. A superseded build can finish, but cannot write over a newer snapshot.
/// Waiting for the preceding task also serializes any write that was already in progress.
@MainActor
final class WidgetSnapshotPublisher {
    private var pending: Task<Void, Never>?
    private let reload: @Sendable () -> Void

    init(reload: @escaping @Sendable () -> Void = { WidgetSnapshotWriter.reloadTimelines() }) {
        self.reload = reload
    }

    deinit { pending?.cancel() }

    @discardableResult
    func publish(activity: Activity, sets: [SetEntry], dir: String) -> Task<Void, Never> {
        publish(dir: dir) { WidgetSnapshot.make(activity: activity, sets: sets) }
    }

    /// The builder is injectable so completion-order races can be reproduced without WidgetKit.
    @discardableResult
    func publish(dir: String, makeSnapshot: @escaping @Sendable () -> WidgetSnapshot) -> Task<Void, Never> {
        let previous = pending
        previous?.cancel()
        let reload = reload
        let next = Task.detached(priority: .utility) {
            await previous?.value
            guard !Task.isCancelled else { return }
            let snapshot = makeSnapshot()
            guard !Task.isCancelled else { return }
            if WidgetSnapshotWriter.write(snapshot, dir: dir) == .written { reload() }
        }
        pending = next
        return next
    }
}
