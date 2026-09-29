// Port of src/ProjectIndex.cs (SetEntry, PluginStat, PluginHealth)
import Foundation

/// One .als in the catalog. A value type: a scan publishes a fresh array, and a set's identity
/// is its path (`Identifiable`), so a row keeps its identity when a rescan re-reads the file.
public struct SetEntry: Identifiable, Hashable, Sendable {
    public var path = ""
    public var name = ""
    public var projectName = ""
    public var modified = Date.distantPast
    public var created = Date.distantPast
    public var size: Int64 = 0
    public var isBackup = false

    public var creator = ""
    public var tempo = 0.0
    /// "C Major"; empty on Live versions with no overall key.
    public var key = ""
    /// 0..11; we filter by it — "C#" and "Db" are one note.
    public var scaleRoot = -1
    public var scaleIndex = -1
    public var tracks = 0
    public var missingFiles = 0
    public var totalRefs = 0
    public var plugins: [String] = []
    /// Parallel to `plugins`, "" when unknown.
    public var pluginVendors: [String] = []
    /// The vendor from VST3/AU rather than from a browser folder.
    public var pluginVendorConfident: [Bool] = []
    /// "vst3:…" / "vst2:…" / "au:…", parallel to `plugins`.
    public var pluginUids: [String] = []
    public var error = ""

    /// The samples the set plays: resolved paths of its SampleRef dependencies that were found,
    /// without repeats. Lost ones are not here — a file that is not on disk belongs to no library.
    public var samples: [String] = []
    /// Parallel to `samples`: the size recorded in the set (OriginalFileSize), or the length on
    /// disk when the set did not record one.
    public var sampleSizes: [Int64] = []

    // Not cached to disk: they change without the set itself being edited.
    /// How many of the set's plugins are not installed; recomputed against the inventory.
    public var missingPlugins = 0
    /// Whether there is anything to listen to next to the project.
    public var hasRenders = false
    /// Names of the files that really can be previewed (same selection as `RenderScan.find`), so
    /// a set can be searched by the name of a render.
    public var renderNames: [String] = []
    /// The weight of the whole project folder and how many files are in it.
    public var projectSize: Int64 = 0
    public var projectFiles = 0

    /// How many more sets of the same folder are hidden under this row. Filled by
    /// `ProjectIndex.collapseByFolder` — it depends on the filters rather than on the set.
    public var collapsedCount = 0

    public init() {}

    public var id: String { path }

    /// A set's identity is its path; equality (synthesized) still compares every field so that
    /// views can detect a changed set.
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }

    /// "12.4.3" out of "Ableton Live 12.4.3".
    public var shortVersion: String {
        guard !creator.isEmpty, let i = creator.lastIndex(of: " ") else { return creator }
        let rest = creator[creator.index(after: i)...]
        return rest.isEmpty ? creator : String(rest)
    }

    public var directory: String { (path as NSString).deletingLastPathComponent }

    /// The project folder — the "… Project" Live creates, with all the Samples inside. If a set
    /// lies on its own, outside such a folder, its own folder is the project. Pure string work
    /// on the path (no file system), so it is cheap enough to ask in hot places.
    public var projectDir: String { SetEntry.projectFolder(ofSetAt: path)?.folder ?? directory }

    /// The shelf a project lies on: the name of the folder containing the "* Project" folder.
    /// For ".../Series 2/somnitelno/X Project/X.als" that is "somnitelno".
    public var place: String {
        if let hit = SetEntry.projectFolder(ofSetAt: path) {
            return SetEntry.name(of: (hit.folder as NSString).deletingLastPathComponent)
        }
        // Not in a "* Project" folder — the parent of the folder holding the .als.
        let dir = directory
        let parent = (dir as NSString).deletingLastPathComponent
        return SetEntry.name(of: parent == dir || parent.isEmpty ? dir : parent)
    }

    /// The nearest "* Project" folder above, otherwise simply the parent folder's name.
    var projectNameFromPath: String {
        if let hit = SetEntry.projectFolder(ofSetAt: path) {
            return String(hit.name.dropLast(" Project".count))
        }
        return (directory as NSString).lastPathComponent
    }

    /// Looks at the set's folder and up to three ancestors for a name ending in " Project".
    static func projectFolder(ofSetAt path: String) -> (folder: String, name: String)? {
        var d = (path as NSString).deletingLastPathComponent
        for _ in 0..<4 {
            let n = (d as NSString).lastPathComponent
            if n.lowercased().hasSuffix(" project") { return (d, n) }
            let parent = (d as NSString).deletingLastPathComponent
            if parent == d || parent.isEmpty { break }
            d = parent
        }
        return nil
    }

    /// Last path component; "" for the file system root.
    private static func name(of path: String) -> String {
        let n = (path as NSString).lastPathComponent
        return n == "/" ? "" : n
    }
}

public struct PluginStat: Sendable {
    public var name = ""
    public var vendor = ""
    public var vendorConfident = false
    public var sets = 0

    public var uid = ""
    public var match: MatchKind = .missing
    /// nil if there is no such plugin on the machine.
    public var installed: InstalledPlugin?

    public init() {}

    public var isInstalled: Bool { match != .missing }
    public var isUnused: Bool { sets == 0 }

    /// "VST3" / "VST2" / "AU" — the format comes from the installed one, otherwise from the id.
    public var format: String {
        if let p = installed, match == .exact { return p.format }
        if uid.hasPrefix("vst3:") { return "VST3" }
        if uid.hasPrefix("vst2:") { return "VST2" }
        if uid.hasPrefix("au:") { return "AU" }
        return installed?.format ?? ""
    }

    /// The plugin's category from VST3/AU (Mastering, Reverb, Synth, Dynamics and so on).
    public var fxType: String {
        guard let cat = installed?.category.trimmingCharacters(in: .whitespaces), !cat.isEmpty else { return "" }
        func isGeneric(_ s: String) -> Bool { s.caseInsensitiveCompare("Fx") == .orderedSame }

        if cat.contains("|") {
            let parts = cat.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if var last = parts.last {
                if (isGeneric(last) || last.caseInsensitiveCompare("Instrument") == .orderedSame), parts.count > 1 {
                    last = parts[parts.count - 2]
                }
                if !isGeneric(last) { return last }
            }
        }
        return isGeneric(cat) ? "" : cat
    }
}

/// A summary of the library's plugins — what the cards show.
public struct PluginHealth: Equatable, Sendable {
    /// distinct plugins occurring in the sets
    public var used = 0
    /// of those, installed (an exact match)
    public var installed = 0
    /// present, but in another format
    public var otherFormat = 0
    /// not installed at all
    public var missing = 0
    /// how many are installed on the machine in total
    public var installedTotal = 0
    /// of those, occurring in no set at all
    public var installedUnused = 0
    /// Live remembers them, but the file is no longer on disk
    public var filesGone = 0

    public init() {}
}
