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

    /// Called whenever the catalog is ready: builds the snapshot off the main thread, writes it and,
    /// when it changed, reloads the widget's timelines.
    static func publish(activity: Activity, sets: [SetEntry], dir: String) {
        Task.detached(priority: .utility) {
            let snapshot = WidgetSnapshot.make(activity: activity, sets: sets)
            if write(snapshot, dir: dir) == .written, usesDefaultFolder {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
