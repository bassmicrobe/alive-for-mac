// Port of src/SampleIndex.cs (model and rules; the walk, prints and cache are in their own files).
// Mac-only change: an immutable, index-based snapshot (structs referring to each other by array
// position) instead of a graph of objects with parent pointers. The cache already stores parents
// by position, a published index is never modified, and nothing has to break a retain cycle.
import Foundation

/// A folder of the sample library. Only folders with a sample somewhere below them become nodes;
/// the rest (a folder of presets, Live's "Ableton Folder Info") pass their weight up to the
/// nearest one that does.
public struct SampleFolder: Sendable, Equatable {
    public var path = ""
    public var name = ""
    /// Position of the parent in `SampleIndex.folders`; nil for a root.
    public var parent: Int?
    /// Subfolders with at least one sample below them.
    public var children: [Int] = []
    /// The samples lying directly in this folder (positions in `SampleIndex.files`).
    public var files: [Int] = []
    /// Samples over the whole subtree.
    public var totalSamples = 0
    /// Every file over the whole subtree, samples or not — "how much room does this pack take"
    /// is about the whole pack.
    public var totalBytes: Int64 = 0
    /// The folder's own dates, as Finder shows them; nil when unknown. Created is when it
    /// appeared on this disk — a pack unpacked two years ago and never touched says so here.
    public var created: Date?
    public var modified: Date?

    public init() {}
}

public struct SampleFile: Sendable, Equatable {
    public var name = ""
    public var size: Int64 = 0
    /// Position of the containing folder in `SampleIndex.folders`.
    public var folder = 0
    /// An AIFF the preview cannot open — in practice Ableton's own compressed AIFC, which is
    /// most of Live's packs. Only Live plays it; the walk finds out once.
    public var silent = false
    /// The file's own dates (nil when unknown). A pack keeps its author's Modified; Created is
    /// when the file landed here.
    public var created: Date?
    public var modified: Date?
    /// A hash of the whole content, taken only for a file with a namesake of the same size
    /// somewhere in the library (see `SamplePrints`). Name and size alone also pair a pack's Dry
    /// and Wet takes of one sound: different recordings of equal length. 0 — not taken, or the
    /// file would not open.
    public var print: UInt64 = 0

    public init() {}

    /// Whether the preview can play it: by the extension, and for an AIFF by what the walk found
    /// in its header.
    public var canPreview: Bool { !silent && SampleIndex.canPreview(name) }
}

/// The sample library: every folder the user pointed at, walked in the background and cached to
/// disk. Published whole; a published index is never modified.
public struct SampleIndex: Sendable {
    /// Positions in `folders` of the roots.
    public var roots: [Int] = []
    /// Parents before children.
    public var folders: [SampleFolder] = []
    public var files: [SampleFile] = []

    public static let empty = SampleIndex()

    public init() {}

    public var totalSamples: Int { roots.reduce(0) { $0 + folders[$1].totalSamples } }
    public var totalBytes: Int64 { roots.reduce(Int64(0)) { $0 + folders[$1].totalBytes } }

    public func path(of file: Int) -> String {
        SampleIndex.combine(folders[files[file].folder].path, files[file].name)
    }

    // MARK: what counts

    /// Upstream's list, plus `.aifc`: upstream's `IsAiffName` accepts it but its list does not.
    private static let extensions: Set<String> =
        [".wav", ".aif", ".aiff", ".aifc", ".flac", ".ogg", ".mp3", ".m4a", ".rx2", ".rex"]
    private static let playable: Set<String> = [".wav", ".aif", ".aiff", ".aifc", ".flac", ".mp3", ".m4a"]

    /// A file Live can load as a sample. "._name.wav" is not one: that is the AppleDouble
    /// resource fork packs made on a Mac carry beside every file, with no sound inside.
    public static func isSampleName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("._"), let ext = dotExtension(name) else { return false }
        return extensions.contains(ext)
    }

    /// What the preview can play: AVFoundation decodes WAV, AIFF, FLAC, MP3 and M4A. OGG and REX
    /// stay silent.
    public static func canPreview(_ name: String) -> Bool {
        guard let ext = dotExtension(name) else { return false }
        return playable.contains(ext)
    }

    /// ".wav" for "a.WAV"; nil when there is no extension ("a" or ".wav" alone).
    static func dotExtension(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        return name[dot...].lowercased()
    }

    /// Folders walked for their weight only: Live's "Ableton Folder Info" (its .ogg browser
    /// previews would otherwise pass for samples — 9,491 of them in the packs on the upstream
    /// development machine), Backup, and project folders — a project that happens to lie in a
    /// sample folder does not make its recordings a library.
    public static func isWeightOnly(_ dirName: String) -> Bool {
        let n = dirName.lowercased()
        return n == "ableton folder info" || n == "backup" || n.hasSuffix(" project")
    }

    // MARK: roots

    /// A path in comparable form: standardized, without a trailing slash.
    public static func norm(_ p: String) -> String {
        var s = (p as NSString).standardizingPath
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public static func containsPath(_ list: [String], _ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let n = norm(path).lowercased()
        return list.contains { norm($0).lowercased() == n }
    }

    /// Whether `path` lies strictly inside `root`. Compared as full paths, or ".../Samples2"
    /// would pass for ".../Samples".
    public static func inside(_ path: String, _ root: String) -> Bool {
        guard !path.isEmpty, !root.isEmpty else { return false }
        let p = norm(path).lowercased(), r = norm(root).lowercased()
        return p.count > r.count + 1 && p.hasPrefix(r == "/" ? r : r + "/")
    }

    /// The roots that get walked: switched on, and not lying inside another switched-on root —
    /// such a one is part of that root's tree already, and walking it twice would count its
    /// samples twice.
    public static func effective(_ roots: [String], disabled: [String]) -> [String] {
        var on: [String] = []
        for r in roots where !r.isEmpty && !containsPath(disabled, r) && !containsPath(on, r) { on.append(r) }
        return on.filter { r in !on.contains { $0 != r && inside(r, $0) } }
    }

    static func combine(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    // MARK: shape

    public func rootOf(_ folder: Int) -> Int {
        var f = folder
        while let p = folders[f].parent { f = p }
        return f
    }

    /// Where something lies, short: the way from its root down to its folder ("Cymatics/Kicks"),
    /// or the root in full for what lies right in it — two roots are easily both called
    /// "Samples". A nil folder gives "".
    public func location(of folder: Int?) -> String {
        guard let folder else { return "" }
        let root = rootOf(folder)
        if folder == root { return folders[root].path }
        let base = folders[root].path
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return String(folders[folder].path.dropFirst(trimmed.count + 1))
    }

    /// The folder's top-level ancestor below its root: a pack, or a vendor's folder of packs.
    public func packFolder(of folder: Int) -> Int {
        var f = folder
        while let p = folders[f].parent, folders[p].parent != nil { f = p }
        return f
    }

    /// Folder position by lowercased path.
    public func folderLookup() -> [String: Int] {
        var m: [String: Int] = [:]
        m.reserveCapacity(folders.count)
        for (i, f) in folders.enumerated() { m[f.path.lowercased()] = i }
        return m
    }

    /// True when `folder` is `ancestor` or lies below it.
    public func folder(_ folder: Int, isWithin ancestor: Int) -> Bool {
        var f: Int? = folder
        while let x = f {
            if x == ancestor { return true }
            f = folders[x].parent
        }
        return false
    }

    // MARK: subsets and merging

    /// The same index without the roots that are no longer switched on — a folder removed in the
    /// dialog leaves the tree at once rather than after the next walk.
    public func only(_ roots: [String], disabled: [String]) -> SampleIndex {
        let keep = SampleIndex.effective(roots, disabled: disabled)
        let kept = self.roots.filter { SampleIndex.containsPath(keep, folders[$0].path) }
        if kept.count == self.roots.count { return self }
        return SampleIndex.combining(kept.map { subtree(root: $0) })
    }

    /// One root's tree as an index of its own (renumbered).
    func subtree(root: Int) -> SampleIndex {
        var order: [Int] = []
        var stack = [root]
        while let f = stack.popLast() {
            order.append(f)
            stack.append(contentsOf: folders[f].children.reversed())
        }
        var newFolder: [Int: Int] = [:]
        for (n, old) in order.enumerated() { newFolder[old] = n }
        var out = SampleIndex()
        out.roots = [0]
        for old in order {
            var f = folders[old]
            f.parent = f.parent.flatMap { newFolder[$0] }
            f.children = f.children.compactMap { newFolder[$0] }
            let mine = out.folders.count
            f.files = f.files.map { fi in
                var file = files[fi]
                file.folder = mine
                out.files.append(file)
                return out.files.count - 1
            }
            out.folders.append(f)
        }
        return out
    }

    /// Several single-root indexes as one (positions shifted).
    static func combining(_ parts: [SampleIndex]) -> SampleIndex {
        var out = SampleIndex()
        for part in parts {
            let fOff = out.folders.count, sOff = out.files.count
            out.roots.append(contentsOf: part.roots.map { $0 + fOff })
            for var f in part.folders {
                f.parent = f.parent.map { $0 + fOff }
                f.children = f.children.map { $0 + fOff }
                f.files = f.files.map { $0 + sOff }
                out.folders.append(f)
            }
            for var s in part.files {
                s.folder += fOff
                out.files.append(s)
            }
        }
        return out
    }
}
