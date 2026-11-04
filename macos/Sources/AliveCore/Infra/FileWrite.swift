// Mac-only: writing a cache file only when its content really changed, and a text data file
// with its previous version kept as `.bak`.
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

    /// Writes a data file whole or not at all — into a temporary file beside it, then swapped in
    /// — with the previous version kept as `<file>.bak` (upstream `Settings.WriteFile`, 9ce4b4b:
    /// written straight over, a machine switched off halfway left a stump in place of a file
    /// nothing can rebuild, like notes.cfg). For the text `.cfg` files; the binary caches are
    /// rebuilt from the disk and stay on `writeAtomicallyIfChanged`.
    ///
    /// Skipped when the file already holds exactly this content: a second save of the same text
    /// must not push the real previous version out of `.bak`. Returns whether the file was
    /// written. A backup that cannot be made is logged and does not stop the save.
    @discardableResult
    public static func writeKeepingBackup(_ data: Data, to path: String) throws -> Bool {
        let fm = FileManager.default
        if let existing = fm.contents(atPath: path), existing == data { return false }
        try ensure((path as NSString).deletingLastPathComponent)

        let temp = path + ".tmp"
        do {
            try data.write(to: URL(fileURLWithPath: temp))
            if fm.fileExists(atPath: path) { keepAsBackup(path) }
            try swapIn(temp, over: path)
        } catch {
            try? fm.removeItem(atPath: temp)
            throw error
        }
        return true
    }

    @discardableResult
    public static func writeKeepingBackup(_ text: String, to path: String) throws -> Bool {
        try writeKeepingBackup(Data(text.utf8), to: path)
    }

    /// Copies the current file to `<file>.bak` through a part file, so the older backup stays
    /// whole until the new one is complete.
    private static func keepAsBackup(_ path: String) {
        let fm = FileManager.default
        let backup = path + ".bak", part = backup + ".part"
        let name = (path as NSString).lastPathComponent
        do {
            try? fm.removeItem(atPath: part)
            try fm.copyItem(atPath: path, toPath: part)
            try swapIn(part, over: backup)
        } catch {
            try? fm.removeItem(atPath: part)
            Diag.fail("back up \(name) before writing", error)
        }
    }

    /// rename(2): replaces the target in one step, so there is no moment without a file.
    private static func swapIn(_ temp: String, over path: String) throws {
        guard rename(temp, path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSFilePathErrorKey: path])
        }
    }
}
