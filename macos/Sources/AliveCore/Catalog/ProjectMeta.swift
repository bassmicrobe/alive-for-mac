// Port of src/ProjectMeta.cs
import Foundation

/// How a change to the tags and notes ended, so the one who asked can tell the person.
public enum StoreSave: Equatable, Sendable {
    case saved
    /// The file could not be read, so nothing was written over it and the change was not taken
    /// (see `AppHome.readStore`): saving later reads the file again first.
    case unread
    /// The write itself failed (logged).
    case failed
}

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
    /// notes.cfg is there but could not be read (another program held it). Saving then would put
    /// the few entries made since in place of every tag and note on disk, so nothing is saved
    /// until the file has been read (upstream `_unread`, 9ce4b4b; here a save reads it again).
    private var unread = false

    /// The tag set may have grown — time for the window to rebuild its list. Called on the
    /// calling thread of `set`, outside the lock.
    public var onChanged: (@Sendable () -> Void)?

    public init(dir: String) { self.dir = dir }

    private var filePath: String { AppHome.file("notes.cfg", in: dir) }

    // MARK: reading

    private func loaded() -> [String: Entry] {
        if let m = byDir { return m }
        let read = AppHome.readStore(filePath)
        unread = read.isUnread
        let m = Self.parse(read.lines)
        byDir = m
        return m
    }

    private static func parse(_ lines: [String]) -> [String: Entry] {
        var m: [String: Entry] = [:]
        for raw in lines {
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
        return m
    }

    /// Reads notes.cfg again after it could not be read; nil while it still cannot be. On success
    /// the memory holds what the file holds and saving is allowed again. Lock held.
    private func rereadLocked() -> [String: Entry]? {
        let read = AppHome.readStore(filePath)
        guard !read.isUnread else { return nil }
        let m = Self.parse(read.lines)
        byDir = m
        unread = false
        return m
    }

    /// Tries to read notes.cfg again when it could not be read at start (the person opening the
    /// tags sheet should see the real tags, not an empty copy). True when this copy is now the
    /// file's, or was all along.
    @discardableResult
    public func reloadIfUnread() -> Bool {
        lock.lock()
        _ = loaded()
        guard unread else { lock.unlock(); return true }
        let recovered = rereadLocked() != nil
        let callback = recovered ? onChanged : nil
        lock.unlock()
        callback?()
        return recovered
    }

    // MARK: access

    /// The file could not be read (yet), so nothing is saved over it.
    public var isUnread: Bool {
        lock.lock(); defer { lock.unlock() }
        _ = loaded()
        return unread
    }

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
    ///
    /// While notes.cfg is unread nothing may be saved over it, so the file is read again first:
    /// if that works, the change goes on top of what the file holds and the other entries stay.
    /// If it still fails, the change is not taken and `.unread` comes back — the caller keeps the
    /// person's text and says so. An entry the file already had for this folder, which the person
    /// could not see while the file was unread, is not thrown away: its tags are kept next to the
    /// new ones, and its note stays when the new one is empty.
    @discardableResult
    public func set(_ dir: String, tags: [String], note: String) -> StoreSave {
        guard !dir.isEmpty else { return .saved }
        lock.lock()
        var m = loaded()
        let wasUnread = unread
        if wasUnread {
            guard let fresh = rereadLocked() else {
                lock.unlock()
                Diag.warn("notes.cfg was not read at start; not saving over it")
                return .unread
            }
            m = fresh
        }
        var e = Entry(dir: dir)
        e.tags = Self.parseTags(tags.joined(separator: ","), merging: [])
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if wasUnread, let unseen = m[dir.lowercased()] {
            e.tags = Self.parseTags(Self.joinTags(unseen.tags), merging: e.tags)
            if e.note.isEmpty { e.note = unseen.note }
        }
        m[dir.lowercased()] = e.isEmpty ? nil : e
        byDir = m
        let outcome = save(m)
        let callback = onChanged
        lock.unlock()
        callback?()
        return outcome
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

    private func save(_ m: [String: Entry]) -> StoreSave {
        guard !unread else {
            Diag.warn("notes.cfg was not read at start; not saving over it")
            return .unread
        }
        var lines = ["# Alive - tags and notes, one project folder per key"]
        for e in m.values.sorted(by: { $0.dir < $1.dir }) where !e.isEmpty {
            if !e.tags.isEmpty { lines.append("tags=\(e.dir)\t\(Self.joinTags(e.tags))") }
            if !e.note.isEmpty { lines.append("note=\(e.dir)\t\(Self.escape(e.note))") }
        }
        do { try AppHome.writeKeepingBackup(lines.joined(separator: "\n") + "\n", to: filePath) }
        catch { Diag.fail("notes.cfg write", error); return .failed }
        return .saved
    }
}
