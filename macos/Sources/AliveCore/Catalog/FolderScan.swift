// Port of src/FolderScan.cs (FindFirstFile → FileManager; symlinks, packages, hidden skipped)
import Foundation

/// Walking the folder tree in search of sets, one directory listing per folder with the size and
/// dates taken from the directory entry (nothing is opened for them).
public enum FolderScan {
    public struct Result: Equatable, Sendable {
        public var dirs = 0          // folders visited
        public var files = 0         // files found
        public var unreadable = 0    // folders that would not open
        public var rootFailed = false
    }

    /// A probe copy from the rescue helper is an .als inside a project folder; without this
    /// filter it would turn up in the catalog next to the real set (see src/RescueSession.cs
    /// `RescueProbe.Suffix`).
    static let probeSuffix = ".alive-probe.als"

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
        .fileSizeKey, .creationDateKey, .contentModificationDateKey,
    ]

    /// One entry of a folder.
    public struct Entry: Sendable {
        public let name: String
        public let isDirectory: Bool
        public let isPackage: Bool
        public let size: Int64
        public let created: Date?
        public let modified: Date?
    }

    /// The entries of one folder; symlinks and hidden entries are not handed out. nil: the folder
    /// would not open.
    public static func list(_ dir: String) -> [Entry]? {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: resourceKeys, options: []) else { return nil }
        var out: [Entry] = []
        out.reserveCapacity(items.count)
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }                  // hidden: .DS_Store, ._AppleDouble…
            guard let v = try? item.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            if v.isSymbolicLink == true { continue }             // no loops, no double walks
            if v.isHidden == true { continue }
            out.append(Entry(name: name, isDirectory: v.isDirectory == true, isPackage: v.isPackage == true,
                             size: Int64(v.fileSize ?? 0), created: v.creationDate,
                             modified: v.contentModificationDate))
        }
        return out
    }

    /// Every file with the given extension in the tree. Backup folders are skipped by a flag —
    /// Live breeds those sets itself and the catalog has no use for them. `.app`/package
    /// bundles and hidden folders are never entered. `isCancelled` true stops the walk.
    public static func find(root: String, ext: String, includeBackups: Bool,
                            onFile: (String) -> Void, isCancelled: () -> Bool = { false }) -> Result {
        var res = Result()
        guard !root.isEmpty else { return res }
        let start = URL(fileURLWithPath: root).standardized.path
        var todo = [start]                  // a stack, not recursion: trees can be deep
        var atRoot = true
        let suffix = ext.lowercased()

        while let dir = todo.popLast() {
            if isCancelled() { break }
            res.dirs += 1
            guard let entries = list(dir) else {
                res.unreadable += 1
                if atRoot { res.rootFailed = true }
                atRoot = false
                continue
            }
            atRoot = false
            for e in entries {
                if e.isDirectory {
                    if e.isPackage || e.name.lowercased().hasSuffix(".app") { continue }
                    if !includeBackups && e.name.caseInsensitiveCompare("Backup") == .orderedSame { continue }
                    todo.append(combine(dir, e.name))
                } else if e.name.lowercased().hasSuffix(suffix) {
                    if e.name.lowercased().hasSuffix(probeSuffix) { continue }
                    res.files += 1
                    onFile(combine(dir, e.name))
                }
            }
        }
        return res
    }

    // MARK: weight

    /// How much a folder weighs with everything inside it.
    public struct Weight: Sendable {
        public var bytes: Int64 = 0
        public var files = 0
        /// When a project was saved, from the names of the copies in `Backup`; nil rather than
        /// an empty list: most folders have no Backup.
        public var saves: [Save]?
    }

    /// One save: when, and of which set — the copy carries the name within itself.
    public struct Save: Equatable, Sendable {
        public var when: Date
        /// "angelcore" out of "angelcore [2026-05-22 012035].als"
        public var set: String
    }

    /// The weight of the whole folder, Samples and Backup included: "how much does the project
    /// take" is about space on disk. On every save Live puts a copy of the old file into Backup
    /// and writes the moment of saving into its name — there is no other history of the work
    /// on disk. We take the bracket rather than the file time: a copy's time is the moment of
    /// the PREVIOUS save.
    public static func weigh(root: String, isCancelled: () -> Bool = { false }) -> Weight {
        walkProject(root: root, weigh: true, renders: false, isCancelled: isCancelled).weight
    }

    /// What one walk of a project folder brought in.
    public struct ProjectWalk: Sendable {
        public var weight = Weight()
        /// Unsorted, unpinned candidates; `RenderScan.finish` orders them.
        public var renders: [RenderFile] = []
    }

    /// One traversal of a project folder for everything that lives in it: the weight (with the
    /// Backup save history) and the render candidates. Each folder is listed once; asking only
    /// for renders visits just the folders renders can live in.
    public static func walkProject(root: String, weigh: Bool, renders: Bool,
                                   isCancelled: () -> Bool = { false }) -> ProjectWalk {
        var out = ProjectWalk()
        guard !root.isEmpty, weigh || renders else { return out }
        struct Item { var dir: String; var depth: Int; var inRenderZone: Bool }
        var todo = [Item(dir: root, depth: 0, inRenderZone: renders)]
        while let it = todo.popLast() {
            if isCancelled() { break }
            // Once per folder rather than once per file: inside Backup there can be hundreds.
            let inBackup = (it.dir as NSString).lastPathComponent.caseInsensitiveCompare("Backup") == .orderedSame
            guard let entries = list(it.dir) else { continue }
            var subs: [String] = []
            for e in entries {
                if e.isDirectory { subs.append(e.name); continue }
                guard weigh else { continue }
                out.weight.bytes += e.size
                out.weight.files += 1
                if inBackup, let s = tryBackupStamp(e.name) {
                    if out.weight.saves == nil { out.weight.saves = [] }
                    out.weight.saves?.append(s)
                }
            }
            if it.inRenderZone { RenderScan.collect(entries, in: it.dir, root: root, into: &out.renders) }
            // Pushed in reverse so the sub-folders come off the stack in listing order: which
            // renders make it under the cap depends on that order.
            for name in subs.reversed() {
                let zone = it.inRenderZone && it.depth < RenderScan.maxDepth
                    && !RenderScan.skipDirs.contains(name.lowercased())
                if !weigh && !zone { continue }
                todo.append(Item(dir: combine(it.dir, name), depth: it.depth + 1, inRenderZone: zone))
            }
        }
        return out
    }

    /// The moment of a save from a copy's name: "anything [2026-05-22 012035].als". Parsed by
    /// position rather than with a date formatter: there are thousands of calls, and the format
    /// is written by Live itself and depends neither on the system language nor its date
    /// settings.
    static func tryBackupStamp(_ name: String) -> Save? {
        let c = Array(name.utf16)
        // "[" + "2026-05-22 012035" (17) + "]" + ".als" — exactly 23 characters from the end.
        guard name.lowercased().hasSuffix("].als"),
              let i = c.lastIndex(of: 0x5B), c.count - i == 23,
              c[i + 5] == 0x2D, c[i + 8] == 0x2D, c[i + 11] == 0x20,
              let y = num(c, i + 1, 4), let mo = num(c, i + 6, 2), let d = num(c, i + 9, 2),
              let h = num(c, i + 12, 2), let mi = num(c, i + 14, 2), let se = num(c, i + 16, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, se < 60 else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi; comps.second = se
        let cal = Calendar.current
        guard let when = cal.date(from: comps),
              cal.dateComponents([.year, .month, .day], from: when) == DateComponents(year: y, month: mo, day: d)
        else { return nil }      // the 31st of February out of someone else's file name
        let set = String(decoding: c[0..<i], as: UTF16.self).trimmingCharacters(in: .whitespaces)
        return Save(when: when, set: set)
    }

    private static func num(_ s: [UInt16], _ at: Int, _ len: Int) -> Int? {
        var v = 0
        for k in at..<at + len {
            guard s[k] >= 48 && s[k] <= 57 else { return nil }
            v = v * 10 + Int(s[k] - 48)
        }
        return v
    }

    static func combine(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }
}
