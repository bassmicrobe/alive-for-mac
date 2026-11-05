// Port of src/Settings.cs (Settings.Dir): where everything the program keeps lives.
import Foundation

/// `ALIVE_HOME` moves all of it at once, so a test bench or a screenshot session works on
/// settings, catalog and caches of its own and never touches the owner's. Every store in the
/// core also takes an explicit `dir` so tests never have to mutate the environment.
public enum AppHome {
    public static let defaultFolderName = "Alive for Mac"

    /// The data folder path (not created).
    public static var path: String {
        if let home = ProcessInfo.processInfo.environment["ALIVE_HOME"], !home.isEmpty { return home }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent(defaultFolderName, isDirectory: true).path
    }

    /// Creates the folder if needed and returns it.
    @discardableResult
    public static func ensure(_ dir: String = AppHome.path) throws -> String {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func file(_ name: String, in dir: String = AppHome.path) -> String {
        (dir as NSString).appendingPathComponent(name)
    }

    /// Atomic text write (temp file + rename), UTF-8 without BOM. Creates the folder.
    public static func writeAtomically(_ text: String, to path: String) throws {
        try writeAtomically(Data(text.utf8), to: path)
    }

    public static func writeAtomically(_ data: Data, to path: String) throws {
        try ensure((path as NSString).deletingLastPathComponent)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: reading text files

    /// How a line-based data file came out of `readConfig`.
    public enum ConfigRead: Equatable, Sendable {
        /// No such file: an ordinary first run.
        case missing
        case lines([String])
        /// Not UTF-8 (a hand edit, or the Windows app's ANSI file): decoded with a fallback
        /// encoding, and the original was copied to `<file>.orig` first.
        case recovered([String])
        /// There is a file, but its content cannot be read as text: it was copied to
        /// `<file>.orig` (when possible) and the caller starts from empty.
        case unreadable
        /// There is a file, but the system would not hand over its bytes (no permission, an I/O
        /// error). Nothing is known about what it holds, so a store that rewrites it must not
        /// save over it (see `readStore`).
        case inaccessible
    }

    /// A data file that was found unreadable (or not UTF-8) and the name its original was kept under.
    public struct BackupNotice: Equatable, Sendable {
        public var file: String
        public var copy: String
    }

    private static let noticeGate = NSLock()
    private static var backupNotices: [BackupNotice] = []

    /// Files that were found unreadable (or not UTF-8) and copied aside since the last call;
    /// the UI tells the user once.
    public static func takeBackupNotices() -> [BackupNotice] {
        noticeGate.lock(); defer { noticeGate.unlock() }
        defer { backupNotices = [] }
        return backupNotices
    }

    /// Reads a text file as lines (handles \r\n and a UTF-8 or UTF-16 byte order mark).
    /// A missing file and an unreadable one are different things: the stores rewrite their file
    /// on the next change, and an unreadable file must not be silently replaced by an empty
    /// one — it is copied aside (`<file>.orig`, never over an earlier copy) before that can happen.
    public static func readConfig(_ path: String) -> ConfigRead {
        let name = (path as NSString).lastPathComponent
        // The read itself says why it failed: `fileExists` is false for "no such file" and for "could
        // not be determined" alike (a data folder that denies traversal for a moment), and a store
        // that took the second for the first would start empty and later save over the real file.
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            if isAbsent(error) { return .missing }
            // No copy can be made of bytes the system will not hand over, so there is nothing
            // to announce as "backed up".
            Diag.warn("\(name) exists but cannot be read: \(error.localizedDescription)")
            return .inaccessible
        }
        if data.isEmpty {
            Diag.info("\(name) is empty")
            return .lines([])
        }
        if let text = decodeUTF8(data) { return .lines(splitLines(text)) }
        if let text = decodeUTF16(data) { return .lines(splitLines(text)) }
        if data.contains(0) {
            Diag.warn("\(name) is not a text file")
            noteBackup(path)
            return .unreadable
        }
        // Single-byte legacy text: Windows-1252 first (Latin-1 for the five bytes it lacks).
        let text = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) ?? ""
        Diag.warn("\(name) is not UTF-8; read as Windows-1252")
        noteBackup(path)
        return .recovered(splitLines(text))
    }

    /// Whether a read failed because there is no such file (ENOENT) — the only failure that means
    /// "an ordinary first run". Permission and I/O errors are not absence.
    static func isAbsent(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return ns.code == Int(ENOENT) }
        if ns.domain == NSCocoaErrorDomain,
           ns.code == CocoaError.fileReadNoSuchFile.rawValue || ns.code == CocoaError.fileNoSuchFile.rawValue {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isAbsent(underlying) }
        return false
    }

    /// Lines of a text file; nil when missing or unreadable (see `readConfig`).
    public static func readLines(_ path: String) -> [String]? {
        switch readConfig(path) {
        case .lines(let l), .recovered(let l): return l
        case .missing, .unreadable, .inaccessible: return nil
        }
    }

    /// The lines of a data file for a store that rewrites that file (settings, notes, pins,
    /// previews). `isUnread` is set when the file is there but could not be read at all: this
    /// copy then holds defaults, and saving them would put them in place of everything on disk,
    /// so the store saves nothing until the next start reads the file (upstream `_unread`,
    /// 9ce4b4b). A file that is read but is not text is different: it was backed up by
    /// `readConfig` and the store starts empty — overwriting it is the way out, a flag that
    /// never clears would leave the person unable to save anything.
    public static func readStore(_ path: String) -> (lines: [String], isUnread: Bool) {
        switch readConfig(path) {
        case .lines(let l), .recovered(let l): return (l, false)
        case .missing, .unreadable: return ([], false)
        case .inaccessible:
            Diag.warn("\((path as NSString).lastPathComponent): not read, so nothing will be saved over it")
            return ([], true)
        }
    }

    private static func decodeUTF8(_ data: Data) -> String? {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let body = data.starts(with: bom) ? Data(data.dropFirst(3)) : data
        return String(data: body, encoding: .utf8)
    }

    private static func decodeUTF16(_ data: Data) -> String? {
        guard data.count >= 2, data.count % 2 == 0 else { return nil }
        let b0 = data[data.startIndex], b1 = data[data.startIndex + 1]
        guard (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) else { return nil }
        guard let s = String(data: data, encoding: .utf16) else { return nil }
        return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    /// Copies `path` to the first free `<path>.orig`, `.orig2`, … and remembers the names. Not `.bak`:
    /// that one is the writer's own previous version (`writeKeepingBackup`) and is replaced at every
    /// save, so the only copy of a Shift-JIS file from the Windows app would be gone after two saves.
    private static func noteBackup(_ path: String) {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        var target = path + ".orig"
        var n = 2
        while fm.fileExists(atPath: target) {
            if fm.contentsEqual(atPath: path, andPath: target) { return }    // already copied
            guard n < 10 else {
                Diag.warn("\(name): no free name for a copy of the original (.orig … .orig9 are taken)")
                return
            }
            target = path + ".orig\(n)"; n += 1
        }
        let copy = (target as NSString).lastPathComponent
        do {
            try fm.copyItem(atPath: path, toPath: target)
            Diag.info("kept the original \(name) as \(copy)")
        } catch {
            Diag.fail("back up \(name)", error)
            return
        }
        noticeGate.lock(); defer { noticeGate.unlock() }
        if !backupNotices.contains(where: { $0.file == name }) { backupNotices.append(BackupNotice(file: name, copy: copy)) }
    }
}
