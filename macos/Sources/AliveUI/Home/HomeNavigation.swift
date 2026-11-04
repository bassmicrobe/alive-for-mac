// Port of the selection rules of src/HomeView.cs (9ce4b4b `HasTile`) and of the day menu of the
// year of work (a6c8dc1 `ShowDay`). Pure, so the rules can be tested without a window.
import AliveCore
import Foundation

/// Which tile is selected, as a function of the tiles on screen.
enum HomeSelection {
    /// Only a set with a tile of its own can stay selected: one the search has hidden is invisible,
    /// yet ⌘O and ⌘D would still act on it.
    static func kept(_ path: String?, in rows: [SetEntry]) -> String? {
        guard let path, rows.contains(where: { $0.path == path }) else { return nil }
        return path
    }

    /// ↓ from the search field goes on into the tiles: the picked one stays, otherwise the first.
    static func entry(selected: String?, in rows: [SetEntry]) -> String? {
        kept(selected, in: rows) ?? rows.first?.path
    }
}

/// A project listed under a day of the calendar.
struct DayProject: Identifiable, Equatable {
    let dir: String
    let name: String
    /// The project's newest set, the one its tile shows; nil when the project has left the catalog.
    let setPath: String?
    var id: String { dir }
}

enum HomeDay {
    /// The projects saved on a day (`Activity.projects(on:)`, busiest first, kept in that order)
    /// matched to the catalog. A project that has gone from it stays in the list under its folder's
    /// name, without a set: that day was worked on all the same.
    static func projects(dirs: [String], sets: [SetEntry]) -> [DayProject] {
        var newest: [String: SetEntry] = [:]
        for s in sets where !s.isBackup && !s.projectDir.isEmpty {
            let k = key(s.projectDir)
            if let known = newest[k], !isNewer(s, than: known) { continue }
            newest[k] = s
        }
        var seen = Set<String>()
        return dirs.compactMap { dir in
            guard seen.insert(key(dir)).inserted else { return nil }
            let set = newest[key(dir)]
            return DayProject(dir: dir, name: set?.name ?? (dir as NSString).lastPathComponent, setPath: set?.path)
        }
    }

    private static func isNewer(_ a: SetEntry, than b: SetEntry) -> Bool {
        a.modified != b.modified ? a.modified > b.modified : a.path < b.path
    }

    private static func key(_ dir: String) -> String {
        var d = dir.lowercased()
        while d.count > 1, d.hasSuffix("/") { d.removeLast() }
        return d
    }
}
