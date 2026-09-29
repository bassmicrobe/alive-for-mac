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

    public init(dir: String) { self.dir = dir }

    private var filePath: String { AppHome.file("home.cfg", in: dir) }

    private func pinsLocked() -> [String] {
        if let p = loadedPins { return p }
        var pins: [String] = []
        for raw in AppHome.readLines(filePath) ?? [] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let val = String(line[line.index(after: eq)...])
            if line[..<eq] == "pin", !val.isEmpty, !Self.contains(pins, val) { pins.append(val) }
        }
        loadedPins = pins
        return pins
    }

    private static func contains(_ list: [String], _ v: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(v) == .orderedSame }
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
        guard !path.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        var pins = pinsLocked()
        let nowPinned: Bool
        if let i = pins.firstIndex(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            pins.remove(at: i); nowPinned = false
        } else {
            pins.append(path); nowPinned = true
        }
        loadedPins = pins
        let text = (["# Alive - home page: pinned projects"] + pins.map { "pin=\($0)" }).joined(separator: "\n") + "\n"
        do { try AppHome.writeAtomically(text, to: filePath) } catch { Diag.fail("home.cfg write", error) }
        return nowPinned
    }
}
