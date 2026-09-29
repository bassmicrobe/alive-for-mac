// Port of src/RenderIndex.cs
import Foundation

/// One audio file next to the project — a candidate for "let me hear it".
public struct RenderFile: Equatable, Hashable, Identifiable, Sendable {
    public var path = ""
    /// File name without the extension.
    public var name = ""
    /// Folder relative to the project root; "" is the root itself.
    public var folder = ""
    public var modified = Date.distantPast
    public var size: Int64 = 0
    /// Pinned as the main preview by hand.
    public var pinned = false
    /// How much it looks like a render; see `RenderScan.find`.
    public var score = 0

    public var id: String { path }
    public var ext: String { (path as NSString).pathExtension.uppercased() }
}

/// Finds a project's renders. Treating every .wav in the folder as a render will not do: in
/// "Samples" lie recorded and frozen pieces, hundreds of them, and the freshest is almost
/// certainly not what the person wants to hear. So Samples (along with Backup and Live's own
/// housekeeping folders) is dropped entirely, and the rest is ordered: pinned by hand first,
/// then newest first.
public enum RenderScan {
    static let exts: Set<String> = ["wav", "mp3", "aif", "aiff", "flac", "m4a", "ogg", "wma"]

    /// Folders where finished material usually goes.
    static let renderDirs: Set<String> = [
        "render", "renders", "rendered", "bounce", "bounces", "export", "exports",
        "mixdown", "mixdowns", "master", "masters", "mixes", "out", "output", "preview",
    ]

    /// Folders where renders never live by definition.
    static let skipDirs: Set<String> = [
        "samples", "backup", "ableton project info", "freeze", "frozen", "cache",
    ]

    static let maxFiles = 600
    static let maxDepth = 4

    /// The project root: the nearest "* Project" folder above, otherwise the .als folder itself.
    public static func projectRoot(_ set: SetEntry) -> String { set.projectDir }

    public static func find(_ set: SetEntry, pins: PreviewPins = .shared) -> [RenderFile] {
        let root = projectRoot(set)
        var isDir: ObjCBool = false
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root, isDirectory: &isDir),
              isDir.boolValue else { return [] }

        var list: [RenderFile] = []
        walk(dir: root, root: root, into: &list, depth: 0)

        let pinned = pins.get(root)
        if !pinned.isEmpty {
            for i in list.indices where list[i].path.caseInsensitiveCompare(pinned) == .orderedSame {
                list[i].pinned = true
                list[i].score += 10_000
            }
        }
        // "The latest render" means latest in time, so the date decides everything except manual
        // pinning.
        list.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.modified != b.modified { return a.modified > b.modified }
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return list
    }

    private static func walk(dir: String, root: String, into list: inout [RenderFile], depth: Int) {
        guard depth <= maxDepth, list.count < maxFiles, let entries = FolderScan.list(dir) else { return }
        var rel = dir.count > root.count ? String(dir.dropFirst(root.count)) : ""
        rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let folderScore = self.folderScore(rel)

        var subs: [String] = []
        for e in entries {
            if e.isDirectory { subs.append(e.name); continue }
            if list.count >= maxFiles { return }
            let ext = (e.name as NSString).pathExtension.lowercased()
            guard exts.contains(ext) else { continue }
            var rf = RenderFile()
            rf.path = FolderScan.combine(dir, e.name)
            rf.name = (e.name as NSString).deletingPathExtension
            rf.folder = rel
            rf.modified = e.modified ?? .distantPast
            rf.size = e.size
            rf.score = folderScore
            list.append(rf)
        }
        for name in subs where !skipDirs.contains(name.lowercased()) {
            walk(dir: FolderScan.combine(dir, name), root: root, into: &list, depth: depth + 1)
        }
    }

    static func folderScore(_ rel: String) -> Int {
        if rel.isEmpty { return 60 }                      // right in the project root
        for part in rel.split(separator: "/") where renderDirs.contains(part.lowercased()) { return 100 }
        return 20
    }
}

/// Pinned previews: which file counts as the main one for a project. They live in their own file
/// (`previews.cfg`, `<projectRoot>\t<file>` per line) rather than settings.cfg — there are as
/// many of them as there are projects.
public final class PreviewPins: @unchecked Sendable {
    public static let shared = PreviewPins(dir: AppHome.path)

    private struct Pin { var root: String; var file: String }

    private let dir: String
    private let lock = NSLock()
    private var map: [String: Pin]?     // keyed case-insensitively; the file keeps the original root

    public init(dir: String) { self.dir = dir }

    private var filePath: String { AppHome.file("previews.cfg", in: dir) }

    private func loaded() -> [String: Pin] {
        if let m = map { return m }
        var m: [String: Pin] = [:]
        for line in AppHome.readLines(filePath) ?? [] {
            guard let tab = line.firstIndex(of: "\t"), tab != line.startIndex else { continue }
            let root = String(line[..<tab])
            m[Self.key(root)] = Pin(root: root, file: String(line[line.index(after: tab)...]))
        }
        map = m
        return m
    }

    public func get(_ projectRoot: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return loaded()[Self.key(projectRoot)]?.file ?? ""
    }

    public func set(_ projectRoot: String, file: String) {
        lock.lock(); defer { lock.unlock() }
        var m = loaded()
        m[Self.key(projectRoot)] = Pin(root: projectRoot, file: file)
        map = m
        save(m)
    }

    public func clear(_ projectRoot: String) {
        lock.lock(); defer { lock.unlock() }
        var m = loaded()
        m[Self.key(projectRoot)] = nil
        map = m
        save(m)
    }

    /// Lookup is case-insensitive like upstream's dictionary; trailing separators are ignored.
    private static func key(_ root: String) -> String {
        var r = root
        while r.count > 1, r.hasSuffix("/") { r.removeLast() }
        return r.lowercased()
    }

    private func save(_ m: [String: Pin]) {
        let lines = m.values.filter { !$0.file.isEmpty }.sorted { $0.root < $1.root }
            .map { "\($0.root)\t\($0.file)" }
        do { try AppHome.writeAtomically(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"), to: filePath) }
        catch { Diag.fail("previews.cfg write", error) }
    }
}
