// Mac-only (upstream: PluginInventory.LoadFromFolders / ScanVst3 / AllDirs): walks the plugin
// folders and reads every bundle. Honest about the ceiling, like upstream: this finds files rather
// than plugins, so a VST2 shell is one row.
import Foundation

/// One folder to walk and the format of the bundles expected in it.
struct PluginRoot: Equatable, Sendable {
    var path: String
    var kind: PluginKind

    /// The bundle extension of the format.
    var fileExtension: String {
        switch kind {
        case .vst3: return ".vst3"
        case .vst2: return ".vst"
        default: return ".component"
        }
    }
}

enum PluginBundleScanner {
    /// How deep vendor subfolders may nest ("VST3/Steinberg/Vendor/Foo.vst3").
    static let maxDepth = 6

    /// Every bundle with the root's extension, in a stable order. A bundle is a folder, but for
    /// some plugins it is a plain file, so both count; the walk never goes inside a bundle (a
    /// second .vst3 lies in there, a real binary, and would arrive as a second plugin of the same
    /// name). Vendor folders are entered, symlinked ones once; unreadable folders are skipped.
    static func findBundles(in root: PluginRoot) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let fm = FileManager.default
        var todo: [(path: String, depth: Int)] = [(root.path, 0)]
        while let (dir, depth) = todo.popLast() {
            guard seen.insert((dir as NSString).resolvingSymlinksInPath).inserted,
                  let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted().reversed() where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.lowercased().hasSuffix(root.fileExtension) { out.append(path); continue }
                var isDir: ObjCBool = false
                if depth < maxDepth, fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    todo.append((path, depth + 1))
                }
            }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Reads all bundles of all roots, in parallel; the result keeps the order of the roots and
    /// of the bundles within them, and holds one entry per plugin class (a bundle can hold several).
    static func scan(_ roots: [PluginRoot]) -> [InstalledPlugin] {
        var jobs: [(bundle: String, kind: PluginKind)] = []
        for root in roots {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            jobs.append(contentsOf: findBundles(in: root).map { ($0, root.kind) })
        }
        let work = jobs
        let read: [[InstalledPlugin]?] = Parallel.map(count: work.count) { i in
            switch work[i].kind {
            case .vst3: return PluginBundleReader.readVST3(bundle: work[i].bundle)
            case .vst2: return PluginBundleReader.readVST2(bundle: work[i].bundle)
            default: return PluginBundleReader.readAudioUnit(bundle: work[i].bundle)
            }
        }
        return read.flatMap { $0 ?? [] }
    }
}
