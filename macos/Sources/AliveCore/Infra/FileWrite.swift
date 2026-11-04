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

        let temp = try writeBeside(path, data, tag: "tmp")
        do {
            if fm.fileExists(atPath: path) { keepAsBackup(path) }
            try swapIn(temp, over: path)
        } catch {
            unlink(temp)
            throw error
        }
        return true
    }

    @discardableResult
    public static func writeKeepingBackup(_ text: String, to path: String) throws -> Bool {
        try writeKeepingBackup(Data(text.utf8), to: path)
    }

    /// Copies the current file to `<file>.bak` through a part file, so the older backup stays
    /// whole until the new one is complete. An empty current file (a stump left by a crash, or a
    /// file emptied by hand) is not a version worth keeping: it would push the good `.bak` out,
    /// so the earlier one stays.
    private static func keepAsBackup(_ path: String) {
        let backup = path + ".bak"
        let name = (path as NSString).lastPathComponent
        do {
            let current = try Data(contentsOf: URL(fileURLWithPath: path))
            if current.isEmpty {
                if let kept = FileStat.of(backup), kept.size > 0 {
                    Diag.warn("\(name) is empty; the earlier \(name).bak is kept")
                }
                return
            }
            let part = try writeBeside(backup, current, tag: "part")
            do { try swapIn(part, over: backup) } catch { unlink(part); throw error }
        } catch {
            Diag.fail("back up \(name) before writing", error)
        }
    }

    /// Writes `data` into a new file next to `path` and returns its path; the caller swaps it in
    /// (`swapIn`) or removes it. The name is unique and the file is created with O_EXCL and
    /// O_NOFOLLOW, so a link someone left at a guessable name (`notes.cfg.tmp`) is never written
    /// through: the write would otherwise truncate whatever it points at. Synced before it returns,
    /// so the rename cannot publish a file whose bytes are still only in memory. The mode is the
    /// one `Data.write` gave (0666 less the umask).
    private static func writeBeside(_ path: String, _ data: Data, tag: String) throws -> String {
        let temp = path + ".\(tag)-" + UUID().uuidString
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o666)
        guard fd >= 0 else { throw posixError(errno, temp) }
        var done = false
        defer {
            close(fd)
            if !done { unlink(temp) }
        }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let n = write(fd, buffer.baseAddress! + written, buffer.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw posixError(errno, temp)
                }
                written += n
            }
        }
        guard fsync(fd) == 0 else { throw posixError(errno, temp) }
        done = true
        return temp
    }

    /// rename(2): replaces the target in one step, so there is no moment without a file. A link
    /// at the target is replaced itself, not followed.
    private static func swapIn(_ temp: String, over path: String) throws {
        guard rename(temp, path) == 0 else { throw posixError(errno, path) }
    }

    private static func posixError(_ code: Int32, _ path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
