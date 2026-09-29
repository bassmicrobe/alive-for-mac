// Port of src/Diag.cs: a log of one run, alive.log in the data folder.
import Foundation

/// The program is portable and depends on someone else's machine; every caught error is
/// written here so that "it does not scan anything" comes with something to go on. One file,
/// truncated at each start — what is needed is exactly the run that broke. Log text is English.
public enum Diag {
    private static let gate = NSLock()
    private static var logPath: String?

    public static var currentLogPath: String? { gate.lock(); defer { gate.unlock() }; return logPath }
    public static func defaultLogPath(dir: String = AppHome.path) -> String { AppHome.file("alive.log", in: dir) }

    /// Truncates the log and writes the environment snapshot.
    public static func start(dir: String = AppHome.path) {
        gate.lock()
        do {
            try AppHome.ensure(dir)
            let path = defaultLogPath(dir: dir)
            try Data().write(to: URL(fileURLWithPath: path))
            logPath = path
        } catch {
            logPath = nil
        }
        gate.unlock()
        append(snapshot())
    }

    public static func stop() { gate.lock(); logPath = nil; gate.unlock() }

    public static func info(_ text: String) { append(stamp() + "  " + text) }
    public static func warn(_ text: String) { append(stamp() + "  WARN " + text) }

    /// `fail("scan root", error)`.
    public static func fail(_ context: String, _ error: Error?) {
        let detail = error.map { String(describing: $0) } ?? "unknown error"
        append(stamp() + "  " + context + " FAILED: " + detail)
    }

    private static func stamp() -> String { format("HH:mm:ss") }

    private static func format(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: Date())
    }

    /// The home folder is written as `~`: a log gets attached to bug reports, and the user name
    /// inside every path is nobody's business but the owner's.
    static func redacted(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard home.count > 1 else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    private static func append(_ text: String) {
        gate.lock(); defer { gate.unlock() }
        guard let path = logPath, let data = (redacted(text) + "\n").data(using: .utf8),
              let h = FileHandle(forWritingAtPath: path) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    }

    /// Everything worth knowing about someone else's machine, in one piece.
    public static func snapshot(env: LiveEnvironment? = nil) -> String {
        let pi = ProcessInfo.processInfo
        let e = env ?? LiveEnvironment.detect()
        let lines = [
            "Alive for Mac   " + format("yyyy-MM-dd HH:mm:ss"),
            "macOS      " + pi.operatingSystemVersionString,
            "cpus       \(pi.activeProcessorCount)",
            "Live       " + (e.installDir.isEmpty ? "not found" : e.installDir),
            "prefs      " + (e.newestPrefsFolder ?? "not found"),
            "library    " + e.userLibrary,
        ]
        return lines.joined(separator: "\n")
    }
}
