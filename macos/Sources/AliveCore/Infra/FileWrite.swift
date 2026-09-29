// Mac-only: writing a cache file only when its content really changed.
import Foundation

extension AppHome {
    /// Atomic write that is skipped when the file already holds exactly `data` (a no-op rescan
    /// must not touch the cache: its mtime is how other tools notice a change). Returns whether
    /// the file was written.
    @discardableResult
    public static func writeAtomicallyIfChanged(_ data: Data, to path: String) throws -> Bool {
        if let current = FileStat.of(path), current.size == Int64(data.count),
           let existing = FileManager.default.contents(atPath: path), existing == data {
            return false
        }
        try writeAtomically(data, to: path)
        return true
    }
}
