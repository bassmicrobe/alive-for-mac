// Port of src/ProjectMeta.cs
import Foundation

/// Tags and notes written by the user, in `notes.cfg` next to the settings — data about
/// projects, not a program setting.
///
/// The key is the project folder, not the path to the .als. A project has a dozen versions
/// lying next to each other, and tags bound to a file would have to be re-applied to each one;
/// besides, "final2.als" appears only after the project has been marked. Tags come with no
/// vocabulary: whatever the person writes is what it is.
///
/// File format (upstream's): `tags=<dir>\t<a, b, c>` and `note=<dir>\t<escaped text>` per line.
public final class ProjectMeta: @unchecked Sendable {
    public static let shared = ProjectMeta(dir: AppHome.path)

    private struct Entry {
        var dir: String
        var tags: [String] = []
        var note = ""
        var isEmpty: Bool { tags.isEmpty && note.isEmpty }
    }

    private let dir: String
    private let lock = NSLock()
    private var byDir: [String: Entry]?    // keyed lowercased

    /// The tag set may have grown — time for the window to rebuild its list. Called on the
    /// calling thread of `set`, outside the lock.
    public var onChanged: (@Sendable () -> Void)?

    public init(dir: String) { self.dir = dir }

    private var filePath: String { AppHome.file("notes.cfg", in: dir) }

    // MARK: reading

    private func loaded() -> [String: Entry] {
        if let m = byDir { return m }
        var m: [String: Entry] = [:]
        for raw in AppHome.readLines(filePath) ?? [] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            let rest = line[line.index(after: eq)...]
            // The path and the value are separated by a tab: paths never contain one, while
            // equals signs and commas turn up all the time.
            guard let tab = rest.firstIndex(of: "\t") else { continue }
            let d = String(rest[..<tab]), val = String(rest[rest.index(after: tab)...])
            if d.isEmpty { continue }
            var e = m[d.lowercased()] ?? Entry(dir: d)
            if key == "tags" { e.tags = Self.parseTags(val, merging: e.tags) }
            else if key == "note" { e.note = Self.unescape(val) }
            else { continue }
            m[d.lowercased()] = e
        }
        byDir = m
        return m
    }

    // MARK: access

    public func tagsOf(_ dir: String) -> [String] {
        guard !dir.isEmpty else { return [] }
        lock.lock(); defer { lock.unlock() }
        return loaded()[dir.lowercased()]?.tags ?? []
    }

    public func noteOf(_ dir: String) -> String {
        guard !dir.isEmpty else { return "" }
        lock.lock(); defer { lock.unlock() }
        return loaded()[dir.lowercased()]?.note ?? ""
    }

    public func hasAnything(_ dir: String) -> Bool {
        guard !dir.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        return !(loaded()[dir.lowercased()]?.isEmpty ?? true)
    }

    /// Every tag already used somewhere, alphabetically — so that the second time the same tag
    /// can be picked from a list instead of recalling how it was spelled.
    public func allTags() -> [String] {
        lock.lock(); defer { lock.unlock() }
        var all: [String] = []
        for e in loaded().values {
            for t in e.tags where !all.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { all.append(t) }
        }
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Replaces tags and note of a project folder; empty ones drop the entry.
    public func set(_ dir: String, tags: [String], note: String) {
        guard !dir.isEmpty else { return }
        lock.lock()
        var m = loaded()
        var e = Entry(dir: dir)
        e.tags = Self.parseTags(tags.joined(separator: ","), merging: [])
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        m[dir.lowercased()] = e.isEmpty ? nil : e
        byDir = m
        save(m)
        let callback = onChanged
        lock.unlock()
        callback?()
    }

    // MARK: text helpers

    /// Parses the string "drum, vocal, beat" into tags (trimmed, no repeats).
    public static func parseTags(_ text: String) -> [String] { parseTags(text, merging: []) }

    static func parseTags(_ text: String, merging existing: [String]) -> [String] {
        var result = existing
        for piece in text.split(separator: ",", omittingEmptySubsequences: true) {
            let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty, !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                result.append(tag)
            }
        }
        return result
    }

    public static func joinTags(_ tags: [String]) -> String { tags.joined(separator: ", ") }

    // The note is multi-line and the file is line-based — breaks go out as "\n".
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Note breaks come back as "\n" (upstream restored "\r\n" for the Windows text box).
    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let next = it.next() else { out.append(c); break }
            out.append(next == "n" ? "\n" : next)
        }
        return out
    }

    private func save(_ m: [String: Entry]) {
        var lines = ["# Alive - tags and notes, one project folder per key"]
        for e in m.values.sorted(by: { $0.dir < $1.dir }) where !e.isEmpty {
            if !e.tags.isEmpty { lines.append("tags=\(e.dir)\t\(Self.joinTags(e.tags))") }
            if !e.note.isEmpty { lines.append("note=\(e.dir)\t\(Self.escape(e.note))") }
        }
        do { try AppHome.writeAtomically(lines.joined(separator: "\n") + "\n", to: filePath) }
        catch { Diag.fail("notes.cfg write", error) }
    }
}
