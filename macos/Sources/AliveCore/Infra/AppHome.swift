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
        /// encoding, and the original was copied to `<file>.bak` first.
        case recovered([String])
        /// There is a file, but its content cannot be read as text: it was copied to
        /// `<file>.bak` (when possible) and the caller starts from empty.
        case unreadable
    }

    private static let noticeGate = NSLock()
    private static var backupNotices: [String] = []

    /// File names that were found unreadable (or not UTF-8) and backed up since the last call;
    /// the UI tells the user once.
    public static func takeBackupNotices() -> [String] {
        noticeGate.lock(); defer { noticeGate.unlock() }
        defer { backupNotices = [] }
        return backupNotices
    }

    /// Reads a text file as lines (handles \r\n and a UTF-8 or UTF-16 byte order mark).
    /// A missing file and an unreadable one are different things: the stores rewrite their file
    /// on the next change, and an unreadable file must not be silently replaced by an empty
    /// one — it is backed up (`<file>.bak`, never over an earlier backup) before that can happen.
    public static func readConfig(_ path: String) -> ConfigRead {
        let name = (path as NSString).lastPathComponent
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let data = FileManager.default.contents(atPath: path) else {
            Diag.warn("\(name) exists but cannot be read")
            noteBackup(path)
            return .unreadable
        }
        if data.isEmpty { return .lines([]) }
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

    /// Lines of a text file; nil when missing or unreadable (see `readConfig`).
    public static func readLines(_ path: String) -> [String]? {
        switch readConfig(path) {
        case .lines(let l), .recovered(let l): return l
        case .missing, .unreadable: return nil
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

    /// Copies `path` to the first free `<path>.bak`, `.bak2`, … and remembers the file name.
    private static func noteBackup(_ path: String) {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        var target = path + ".bak"
        var n = 2
        while fm.fileExists(atPath: target), n < 10 {
            if fm.contentsEqual(atPath: path, andPath: target) { return }    // already backed up
            target = path + ".bak\(n)"; n += 1
        }
        do {
            if !fm.fileExists(atPath: target) { try fm.copyItem(atPath: path, toPath: target) }
            Diag.info("backed up \(name) to \((target as NSString).lastPathComponent)")
        } catch {
            Diag.fail("back up \(name)", error)
        }
        noticeGate.lock(); defer { noticeGate.unlock() }
        if !backupNotices.contains(name) { backupNotices.append(name) }
    }
}
