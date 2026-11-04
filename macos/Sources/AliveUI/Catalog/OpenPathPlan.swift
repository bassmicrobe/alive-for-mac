// Port of MainForm.OpenPaths / FlushPending / AddRoots / SelectSetByPath (src/MainForm.cs): what to
// do with .als files handed to the app ("Open With", `open -a`, a second copy started with a path).
// A path the catalog knows is selected, and so is a project folder (or a file inside one) of a set
// it knows; any other is taken in as a folder to watch.
import Foundation
import AliveCore

struct OpenPathPlan: Equatable {
    /// Catalog paths (exactly as the catalog spells them) to select, in the order given.
    var select: [String] = []
    /// Folders to add as scan roots, without repeats.
    var addRoots: [String] = []
    /// Sets that lie inside a folder already scanned yet are not in the catalog (a Backup copy,
    /// say): nothing to select and no folder to add, so they just open in Live.
    var openDirectly: [String] = []

    static func make(paths: [String], sets: [SetEntry], roots: [String], disabledRoots: [String],
                     fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> OpenPathPlan {
        var plan = OpenPathPlan()
        let catalog = Dictionary(sets.map { (key($0.path), $0.path) }, uniquingKeysWith: { first, _ in first })
        let newestFirst = sets.sorted { $0.modified > $1.modified }
        let active = roots.filter { r in !disabledRoots.contains { same($0, r) } }
        for raw in paths where !raw.isEmpty {
            if let known = catalog[key(raw)] {
                plan.select.append(known)
                continue
            }
            guard fileExists(raw) else { continue }
            let isSet = raw.lowercased().hasSuffix(".als")
            // A set that is not in the catalog (a Backup copy) opens as it is; anything else that
            // lies in a known project belongs to that project.
            if !isSet, let owner = newestFirst.first(where: { contains(root: $0.projectDir, path: raw) }) {
                plan.select.append(owner.path)
                continue
            }
            let folder = isSet ? (raw as NSString).deletingLastPathComponent : raw
            if active.contains(where: { contains(root: $0, path: folder) }) {
                plan.openDirectly.append(raw)
            } else if !plan.addRoots.contains(where: { same($0, folder) }),
                      !roots.contains(where: { same($0, folder) }) {
                plan.addRoots.append(folder)
            }
        }
        return plan
    }

    private static func key(_ path: String) -> String {
        (path as NSString).standardizingPath.lowercased()
    }

    private static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }

    /// `path` is `root` or lies inside it. Matched on whole path components: "Song Project 2/x"
    /// is not inside "Song Project" (upstream's StartsWith took it for that and landed on the
    /// wrong project).
    private static func contains(root: String, path: String) -> Bool {
        let r = key(root), p = key(path)
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }
}
