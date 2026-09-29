// Port of src/LiveEnvironment.cs, macOS edition.
import Foundation

/// An installed Ableton Live application bundle.
public struct LiveInstall: Equatable, Sendable {
    /// `/Applications/Ableton Live 11 Suite.app`
    public let appPath: String
    public let version: LiveVersion

    public var resources: String { appPath + "/Contents/App-Resources" }
    public var isBeta: Bool { version.isBeta }
}

/// A folder of Live's browser sidebar (name Live gives it + the folder).
public struct LivePlace: Equatable, Sendable {
    public var name: String
    public var path: String
}

/// Where THIS machine keeps the roots Live measures its references from. Absolute paths inside
/// sets are often stale (previous Live version, another drive, somebody else's profile), so the
/// only reliable source is the local configuration.
public struct LiveEnvironment: Sendable {
    public var userLibrary = ""
    public var builtin = ""
    public var coreLibrary = ""
    /// The newest installed Live app bundle; empty when none.
    public var installDir = ""
    /// Every installed Live app, newest first.
    public var installs: [LiveInstall] = []
    /// `~/Library/Preferences/Ableton/Live *` folders, sorted oldest → newest.
    public var prefsFolders: [String] = []
    /// The Places of Live's browser over every installed Live, without repeats.
    public var places: [LivePlace] = []
    /// Where Live installs packs (Preferences → Library); empty if it was never set.
    public var packsFolder = ""

    /// Pack name → pack folder, from Library.cfg (look up with `packRoot(named:)`).
    public private(set) var packs: [String: String] = [:]
    private var packKeys: [String: String] = [:]   // lowercased name → key in `packs`

    public init() {}

    public var newestPrefsFolder: String? { prefsFolders.last }

    /// Case-insensitive, like upstream's dictionary.
    public func packRoot(named name: String) -> String? {
        packKeys[name.lowercased()].flatMap { packs[$0] }
    }

    mutating func setPack(_ name: String, _ path: String) {
        if let old = packKeys[name.lowercased()] { packs[old] = nil }
        packs[name] = path
        packKeys[name.lowercased()] = name
    }

    // MARK: detect

    /// `home` and `applicationsDirs` are injectable for tests.
    public static func detect(home: String = NSHomeDirectory(),
                              applicationsDirs: [String]? = nil) -> LiveEnvironment {
        var e = LiveEnvironment()
        let apps = applicationsDirs ?? ["/Applications", home + "/Applications"]
        e.installs = findInstalls(in: apps)
        if let newest = e.installs.first {
            e.installDir = newest.appPath
            e.builtin = newest.resources + "/Builtin"
            e.coreLibrary = newest.resources + "/Core Library"
        }
        e.userLibrary = home + "/Music/Ableton/User Library"

        e.prefsFolders = findPrefsFolders(home: home)
        for folder in e.prefsFolders {      // oldest → newest, so the newest has the last word
            let cfg = folder + "/Library.cfg"
            if FileManager.default.fileExists(atPath: cfg) { e.readLibraryConfig(cfg) }
        }
        if !e.coreLibrary.isEmpty && e.packRoot(named: "Core Library") == nil {
            e.setPack("Core Library", e.coreLibrary)
        }
        return e
    }

    /// `Ableton Live*.app` in the given folders, newest first. The version comes from
    /// `Contents/Info.plist` (`CFBundleShortVersionString`); the app name is the fallback.
    public static func findInstalls(in dirs: [String]) -> [LiveInstall] {
        let fm = FileManager.default
        var result: [LiveInstall] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where name.hasPrefix("Ableton Live") && name.hasSuffix(".app") {
                let app = dir + "/" + name
                guard fm.fileExists(atPath: app + "/Contents/App-Resources") else { continue }
                let version = bundleVersion(app) ?? LiveVersion(name) ?? LiveVersion(numbers: [0], beta: nil)
                result.append(LiveInstall(appPath: app, version: version))
            }
        }
        return result.sorted { $0.version > $1.version }
    }

    private static func bundleVersion(_ app: String) -> LiveVersion? {
        guard let data = FileManager.default.contents(atPath: app + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return nil }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let s = dict[key] as? String, let v = LiveVersion(s) { return v }
        }
        return nil
    }

    /// Preference folders, oldest → newest ("Live 11.1b10" < "Live 11.1" < "Live 12.0b20").
    public static func findPrefsFolders(home: String) -> [String] {
        let root = home + "/Library/Preferences/Ableton"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        let live = names.filter { $0.hasPrefix("Live ") }.compactMap { n -> (String, LiveVersion)? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root + "/" + n, isDirectory: &isDir), isDir.boolValue,
                  let v = LiveVersion(folderName: n) else { return nil }
            return (n, v)
        }
        return live.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { root + "/" + $0.0 }
    }

    // MARK: Library.cfg

    /// Reads one Library.cfg (XML). A broken config is logged and skipped — we make do with what
    /// the defaults found.
    mutating func readLibraryConfig(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return }
        var reader = LibraryConfigReader()
        let stream = ElementStream(onStart: { reader.handle($0) }, onEnd: { _ in })
        if let err = stream.run(data) { Diag.warn("Library.cfg \(path): \(err)") }
        apply(reader)
    }

    private mutating func apply(_ r: LibraryConfigReader) {
        let fm = FileManager.default
        func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
        for (name, path) in r.slices where isDir(path) { setPack(name, path) }
        for (name, path) in r.folders where isDir(path) {
            addPlace(name.isEmpty ? (path as NSString).lastPathComponent : name, path)
        }
        if let p = r.packsFolder, isDir(p) { packsFolder = p }
        if let n = r.projectName, let p = r.projectPath, !n.isEmpty, !p.isEmpty {
            let ul = (p as NSString).appendingPathComponent(n)
            if isDir(ul) { userLibrary = ul }
        }
    }

    /// A Place seen in several versions keeps the name the last read one gives it — configs are
    /// read oldest first, so the newest Live has the last word.
    mutating func addPlace(_ name: String, _ path: String) {
        func norm(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
        if let i = places.firstIndex(where: { norm($0.path).caseInsensitiveCompare(norm(path)) == .orderedSame }) {
            places[i].name = name
        } else {
            places.append(LivePlace(name: name, path: path))
        }
    }
}

/// Collects what Library.cfg says, before the file system is asked about any of it.
struct LibraryConfigReader {
    var slices: [(String, String)] = []
    var folders: [(String, String)] = []
    var packsFolder: String?
    var projectName: String?, projectPath: String?

    mutating func handle(_ e: XMLTag) {
        switch e.name {
        case "LibrarySliceInfo":
            if let p = e.attrs["Path"], let n = e.attrs["DisplayName"], !p.isEmpty, !n.isEmpty {
                slices.append((n, p))
            }
        case "UserFolderInfo":
            if let p = e.attrs["Path"], !p.isEmpty { folders.append((e.attrs["DisplayName"] ?? "", p)) }
        case "PreferredFactoryPacksInstallationPath":
            if let p = e.value, !p.isEmpty { packsFolder = p }
        case "ProjectName": projectName = e.value
        case "ProjectPath": projectPath = e.value
        default: break
        }
    }
}
