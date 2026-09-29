// Port of src/PluginInventory.cs (Load, Installs, LoadFromFolders). Where upstream asks Live's
// database first and walks the folders only when the settings say so, the Mac does both: the
// bundles on disk are the base (Live's Mac database is an SQLite file we do not read), and what
// Live's scanner log knows — VST3 class ids, VST2 ids, categories — is laid on top of them.
import Foundation

/// The folders a load looks in; injectable for tests.
public struct PluginLocations: Sendable {
    public var home: String
    /// The parent of `Components`, `VST` and `VST3`.
    public var systemPlugIns: String
    /// Live's preferences: one folder per installed version.
    public var livePreferences: String

    public init(home: String = NSHomeDirectory(), systemPlugIns: String = "/Library/Audio/Plug-Ins",
                livePreferences: String? = nil) {
        self.home = home
        self.systemPlugIns = systemPlugIns
        self.livePreferences = livePreferences ?? home + "/Library/Preferences/Ableton"
    }

    var userPlugIns: String { home + "/Library/Audio/Plug-Ins" }
}

extension PluginInventory {
    /// What is installed on this machine.
    ///
    /// Default: the bundle folders (Audio Units, VST3 unless switched off, VST2, plus the custom
    /// folders from the settings) combined with the records of Live's scanner log across all its
    /// installs — the newest snapshot wins per identifier, and from the older ones everything whose
    /// file is gone is dropped, otherwise a three-year-old log would resurrect what was removed
    /// long ago. Setting `pluginsFromFolders` skips Live's records and reads the folders only.
    /// `pluginSource` narrows Live's records to one install.
    public static func load(settings: Settings) -> PluginInventory {
        load(settings: settings, locations: PluginLocations())
    }

    public static func load(settings: Settings, locations: PluginLocations) -> PluginInventory {
        var inv = PluginInventory()
        inv.scanned = Date()
        let paths = PathExistsCache()
        var records: [InstalledPlugin] = []

        if !settings.pluginsFromFolders { records = loadLive(settings, locations, paths, into: &inv) }
        let known = Set(records.map { $0.path + "\u{0}" + $0.kind.rawValue })

        var folderCount = 0
        for group in folderGroups(settings, locations) {
            let read = PluginBundleScanner.scan(group.roots).filter { !known.contains($0.path + "\u{0}" + $0.kind.rawValue) }
            folderCount += read.count
            records.append(contentsOf: read)
            if !read.isEmpty { inv.sources.append("\(group.label) · \(read.count)") }
        }
        inv.add(contentsOf: records)

        // The caller logs one summary line (ProjectIndex.refreshInstalled), not one per plugin.
        if inv.all.isEmpty { inv.error = "No plugins found in the plug-in folders — check the paths in Settings" }
        return inv
    }

    /// Live's install folder names, newest first — for the settings window's source list. A folder
    /// gets in merely by having Live's preferences, so the list may hold installs without plugins.
    public static func installs(locations: PluginLocations = PluginLocations()) -> [String] {
        PluginScanDb.versionFolders(root: locations.livePreferences).map { ($0 as NSString).lastPathComponent }
    }

    // MARK: - Live's records

    private static func loadLive(_ settings: Settings, _ locations: PluginLocations, _ paths: PathExistsCache,
                                 into inv: inout PluginInventory) -> [InstalledPlugin] {
        var folders = PluginScanDb.versionFolders(root: locations.livePreferences)
        if !settings.pluginSource.isEmpty {
            folders.removeAll { ($0 as NSString).lastPathComponent.caseInsensitiveCompare(settings.pluginSource) != .orderedSame }
        }
        var out: [InstalledPlugin] = []
        for dir in folders {
            var rec = PluginScanDb.read(versionDir: dir, paths: paths)
            if rec.plugins.isEmpty { continue }
            // The first non-empty snapshot is the principal one: it answers for "Live knows the
            // plugin but the file is gone". In the others such records are simply old.
            if !out.isEmpty { rec.plugins.removeAll { $0.fileMissing } }
            for i in rec.plugins.indices {
                let base = PluginBundleReader.baseName(rec.plugins[i].path)
                if !base.isEmpty, base != rec.plugins[i].name { rec.plugins[i].aliases = [base] }
            }
            let name = (dir as NSString).lastPathComponent
            if inv.sourcePath.isEmpty {
                inv.sourcePath = rec.sourcePath
                inv.liveVersion = name
                inv.scanned = max(rec.scanned, .distantPast)
            }
            inv.sources.append("\(name) · \(rec.plugins.count)")
            out.append(contentsOf: rec.plugins)
        }
        return out
    }

    // MARK: - Folders

    private struct FolderGroup {
        var label: String
        var roots: [PluginRoot]
    }

    /// The folders to walk: the same switches Live has (Preferences → Plug-Ins). Audio Units have
    /// no switch — the system registers every one of them. Custom paths hold several folders,
    /// separated by `;` or new lines.
    private static func folderGroups(_ s: Settings, _ loc: PluginLocations) -> [FolderGroup] {
        func roots(_ kind: PluginKind, _ dir: String, system: Bool = true, custom: [String] = []) -> [PluginRoot] {
            var list: [String] = []
            if system { list = [loc.systemPlugIns + "/" + dir, loc.userPlugIns + "/" + dir] }
            return (list + custom).map { PluginRoot(path: $0, kind: kind) }
        }
        return [
            FolderGroup(label: "Audio Units", roots: roots(.audioUnit, "Components")),
            FolderGroup(label: "VST3", roots: roots(.vst3, "VST3", system: s.vst3SystemOn,
                                                    custom: s.vst3CustomOn ? customFolders(s.vst3CustomPath) : [])),
            FolderGroup(label: "VST", roots: roots(.vst2, "VST",
                                                   custom: s.vst2CustomOn ? customFolders(s.vst2CustomPath) : [])),
        ]
    }

    static func customFolders(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
    }
}
