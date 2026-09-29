// Port of src/Settings.cs. Mac-only addition: the `lang` key (system|en|ja).
import Foundation

/// Search roots and small settings. The format is line-based (`key=value`, `#` comments) so the
/// file can be edited by hand and stays identical to upstream's `settings.cfg`. Keys this build
/// does not know are kept and written back unchanged (`unknownLines`).
public struct Settings: Equatable, Sendable {
    public var roots: [String] = []
    /// A subset of `roots` temporarily excluded from scanning.
    public var disabledRoots: [String] = []
    /// Folders of the sample library — the Samples tab.
    public var sampleRoots: [String] = []
    public var disabledSampleRoots: [String] = []

    /// Columns of the sets list, "Set,Modified:150,BPM:81,…"; empty means the default set.
    /// Stored as is; the list itself parses and builds the string.
    public var setColumns = ""
    public var pluginColumns = ""
    /// Key "samplecols" (an unreleased upstream build used "samplecolumns"; not read).
    public var sampleColumns = ""
    /// One-off repair flag: column order was brought back to the catalog's.
    public var columnsSorted = false
    public var pinnedFirst = false
    public var overviewOpen = true
    /// Turn the translucent window background off. On by default, like upstream (flat window).
    public var disableGlass = true
    /// Kept for file compatibility; the Mac app has native scrolling.
    public var smoothScroll = false
    /// Collapse the sets of one folder into a single row.
    public var groupByFolder = true

    // plugins
    public var pluginsFromFolders = false
    /// Which Live installation to ask: empty = all, newest wins; otherwise a folder name.
    public var pluginSource = ""
    public var vst2CustomOn = false
    public var vst2CustomPath = ""
    public var vst3SystemOn = true
    public var vst3CustomOn = false
    public var vst3CustomPath = ""

    // collecting a project
    public var collectElsewhere = true
    public var collectOtherProjects = true
    public var collectUserLibrary = true
    public var collectFactoryPacks = false
    public var collectToZip = false

    /// Main window frame as "x,y,w,h"; empty until it has been closed once.
    public var windowBounds = ""
    public var windowMaximized = false

    // updates
    public var checkUpdates = false
    /// yyyy-MM-dd
    public var lastUpdateCheck = ""
    public var seenUpdate = ""

    /// Mac-only: UI language, `system`, `en` or `ja`.
    public var lang = Settings.systemLang

    /// Lines with keys this build does not know, in file order — round-tripped verbatim.
    public var unknownLines: [String] = []

    public static let systemLang = "system"
    static let header = "# Alive - folders to scan for projects"
    public static let allowedLangs = ["system", "en", "ja"]

    public init() {}

    public var isFirstRun: Bool { roots.isEmpty }

    public static func filePath(dir: String = AppHome.path) -> String {
        AppHome.file("settings.cfg", in: dir)
    }

    // MARK: load

    public static func load(dir: String = AppHome.path) -> Settings {
        var s = Settings()
        guard let lines = AppHome.readLines(filePath(dir: dir)) else { return s }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                // The header is written afresh on every save; anybody's own comments stay.
                if line != Settings.header { s.unknownLines.append(line) }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !s.apply(key: key, value: val) { s.unknownLines.append(line) }
        }
        return s
    }

    /// Applies one known key; false when the key is not one of ours.
    private mutating func apply(key: String, value v: String) -> Bool {
        if applyList(key, v) { return true }
        if applyFlag(key, v) { return true }
        return applyText(key, v)
    }

    private mutating func applyList(_ key: String, _ v: String) -> Bool {
        switch key {
        case "root": Settings.addUnique(&roots, v)
        case "root_off": Settings.addUnique(&disabledRoots, v)
        case "samplefolder": Settings.addUnique(&sampleRoots, v)
        case "samplefolder_off": Settings.addUnique(&disabledSampleRoots, v)
        default: return false
        }
        return true
    }

    private mutating func applyFlag(_ key: String, _ v: String) -> Bool {
        let on = v == "1"
        switch key {
        case "columnssorted": columnsSorted = on
        case "pinnedfirst": pinnedFirst = on
        case "overviewopen": overviewOpen = on
        case "noglass": disableGlass = on
        case "smoothscroll": smoothScroll = on
        case "nosmoothscroll": smoothScroll = v == "0"   // legacy key
        case "groupbyfolder": groupByFolder = on
        case "pluginfolders": pluginsFromFolders = on
        case "vst2custom": vst2CustomOn = on
        case "vst3system": vst3SystemOn = on
        case "vst3custom": vst3CustomOn = on
        case "collectelsewhere": collectElsewhere = on
        case "collectotherprojects": collectOtherProjects = on
        case "collectuserlibrary": collectUserLibrary = on
        case "collectfactorypacks": collectFactoryPacks = on
        case "collecttozip": collectToZip = on
        case "windowmax": windowMaximized = on
        case "checkupdates": checkUpdates = on
        default: return false
        }
        return true
    }

    private mutating func applyText(_ key: String, _ v: String) -> Bool {
        switch key {
        case "setcolumns": setColumns = v
        case "plugincolumns": pluginColumns = v
        case "samplecols": sampleColumns = v
        case "pluginsource": pluginSource = v
        case "vst2path": vst2CustomPath = v
        case "vst3path": vst3CustomPath = v
        case "window": windowBounds = v
        case "lastupdatecheck": lastUpdateCheck = v
        case "seenupdate": seenUpdate = v
        case "lang": lang = Settings.allowedLangs.contains(v) ? v : Settings.systemLang
        default: return false
        }
        return true
    }

    // Paths are matched case-insensitively (default macOS volumes are case-insensitive too).
    private static func addUnique(_ list: inout [String], _ value: String) {
        guard !value.isEmpty, !list.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
        else { return }
        list.append(value)
    }

    // MARK: save

    /// Serialises to the exact upstream line format (plus `lang`, then unknown lines).
    public func serialized() -> String {
        var out = [Settings.header]
        func flag(_ k: String, _ b: Bool) { out.append("\(k)=\(b ? "1" : "0")") }
        // The file is line-based: a value with a line break (a folder name may have one) would
        // split into a bogus line, so such values are left out and the fact is logged.
        func single(_ k: String, _ v: String) -> String? {
            guard v.contains(where: \.isNewline) else { return v }
            Diag.warn("settings: not saving \(k) with a line break in its value")
            return nil
        }
        func opt(_ k: String, _ v: String) { if !v.isEmpty, let v = single(k, v) { out.append("\(k)=\(v)") } }
        func text(_ k: String, _ v: String) { if let v = single(k, v) { out.append("\(k)=\(v)") } }
        func list(_ k: String, _ vs: [String]) { vs.forEach { if let v = single(k, $0) { out.append("\(k)=\(v)") } } }
        list("root", roots); list("root_off", disabledRoots)
        list("samplefolder", sampleRoots); list("samplefolder_off", disabledSampleRoots)
        flag("pinnedfirst", pinnedFirst); flag("overviewopen", overviewOpen)
        flag("noglass", disableGlass); flag("smoothscroll", smoothScroll)
        flag("groupbyfolder", groupByFolder); flag("pluginfolders", pluginsFromFolders)
        text("pluginsource", pluginSource)
        flag("vst2custom", vst2CustomOn); text("vst2path", vst2CustomPath)
        flag("vst3system", vst3SystemOn); flag("vst3custom", vst3CustomOn)
        text("vst3path", vst3CustomPath)
        flag("collectelsewhere", collectElsewhere); flag("collectotherprojects", collectOtherProjects)
        flag("collectuserlibrary", collectUserLibrary); flag("collectfactorypacks", collectFactoryPacks)
        flag("collecttozip", collectToZip)
        opt("setcolumns", setColumns); opt("plugincolumns", pluginColumns); opt("samplecols", sampleColumns)
        flag("columnssorted", columnsSorted)
        opt("window", windowBounds); flag("windowmax", windowMaximized)
        flag("checkupdates", checkUpdates)
        opt("lastupdatecheck", lastUpdateCheck); opt("seenupdate", seenUpdate)
        out.append("lang=\(lang)")
        out.append(contentsOf: unknownLines)
        return out.joined(separator: "\n") + "\n"
    }

    /// Atomic write (temp file + rename). Throws on I/O failure; callers log via `Diag`.
    public func save(dir: String = AppHome.path) throws {
        try AppHome.writeAtomically(serialized(), to: Settings.filePath(dir: dir))
    }

    /// Re-reads only the root lists from disk (upstream `ReloadRoots`).
    public mutating func reloadRoots(dir: String = AppHome.path) {
        let s = Settings.load(dir: dir)
        roots = s.roots
        disabledRoots = s.disabledRoots
    }
}
