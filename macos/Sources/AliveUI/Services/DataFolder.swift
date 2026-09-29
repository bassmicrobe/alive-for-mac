// Mac-only: where Alive keeps its data files. Stand-in for the core `AppHome`
// (wave 1.5 switches to it): `ALIVE_HOME` or ~/Library/Application Support/Alive for Mac/.
import Foundation

enum DataFolder {
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["ALIVE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Alive for Mac", isDirectory: true)
    }

    /// The folder, created on first use so "open" always has something to show.
    static func ensureExists() throws -> URL {
        let folder = url
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
