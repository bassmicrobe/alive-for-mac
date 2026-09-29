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

    /// Reads a UTF-8 text file split into lines (handles \r\n); nil when missing/unreadable.
    public static func readLines(_ path: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
