// Port of src/HomeStore.cs
import Foundation

/// What the home page remembers: pinned projects, in `home.cfg` (`pin=<path>` per line). A
/// separate file rather than settings.cfg — user data about specific projects, not a program
/// setting. No tags, ratings or collections on purpose: pinning with one press covers 90% of
/// "keep this within reach".
public final class HomeStore: @unchecked Sendable {
    public static let shared = HomeStore(dir: AppHome.path)

    private let dir: String
    private let lock = NSLock()
    private var loadedPins: [String]?
    /// home.cfg is there but could not be read: nothing is saved over it until a read works (see `AppHome.readStore`).
    private var unread = false

    public init(dir: String) { self.dir = dir }

    private var filePath: String { AppHome.file("home.cfg", in: dir) }

    private func pinsLocked() -> [String] {
        if let p = loadedPins { return p }
        let read = AppHome.readStore(filePath)
        unread = read.isUnread
        let pins = Self.parse(read.lines)
        loadedPins = pins
        return pins
    }

    private static func parse(_ lines: [String]) -> [String] {
        var pins: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let val = String(line[line.index(after: eq)...])
            if line[..<eq] == "pin", !val.isEmpty, !contains(pins, val) { pins.append(val) }
        }
        return pins
    }

    /// The pins to change: when the file could not be read at start, it is read again first, and
    /// if that works the change goes on top of what the file holds. Lock held.
    private func pinsForEditLocked() -> [String] {
        let pins = pinsLocked()
        guard unread else { return pins }
        let read = AppHome.readStore(filePath)
        guard !read.isUnread else { return pins }
        unread = false
        return Self.parse(read.lines)
    }

    private static func contains(_ list: [String], _ v: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(v) == .orderedSame }
    }

    /// The file could not be read (yet), so pins changed since are kept in memory only.
    public var isUnread: Bool {
        lock.lock(); defer { lock.unlock() }
        _ = pinsLocked()
        return unread
    }

    /// Pin order is kept: pinned first, shown first.
    public var pins: [String] {
        lock.lock(); defer { lock.unlock() }
        return pinsLocked()
    }

    public func isPinned(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Self.contains(pinsLocked(), path)
    }

    /// Returns the new state (true = now pinned).
    @discardableResult
    public func togglePin(_ path: String) -> Bool {
        togglePinReportingSave(path).isPinned
    }

    /// `togglePin`, and how the save ended: while the file cannot be read the pin is kept in memory
    /// only (`.unread`), which the caller tells the person.
    public func togglePinReportingSave(_ path: String) -> (isPinned: Bool, save: StoreSave) {
        guard !path.isEmpty else { return (false, .saved) }
        lock.lock(); defer { lock.unlock() }
        var pins = pinsForEditLocked()
        let nowPinned: Bool
        if let i = pins.firstIndex(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            pins.remove(at: i); nowPinned = false
        } else {
            pins.append(path); nowPinned = true
        }
        loadedPins = pins
        let text = (["# Alive - home page: pinned projects"] + pins.map { "pin=\($0)" }).joined(separator: "\n") + "\n"
        if unread {
            Diag.warn("home.cfg was not read at start; not saving over it")
            return (nowPinned, .unread)
        }
        do { try AppHome.writeKeepingBackup(text, to: filePath) } catch {
            Diag.fail("home.cfg write", error)
            return (nowPinned, .failed)
        }
        return (nowPinned, .saved)
    }
}
