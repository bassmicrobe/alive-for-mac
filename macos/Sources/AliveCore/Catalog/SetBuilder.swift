// Port of src/ProjectIndex.cs (ProjectIndex.Build): one .als → one SetEntry
import Foundation

enum SetBuilder {
    /// What the file system said about the .als (size and times, times quantized to ticks).
    struct FileStamp {
        var size: Int64
        var modified: Date
        var created: Date
    }

    static func stamp(of path: String) -> FileStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        func quantized(_ d: Date?) -> Date {
            guard let d else { return .distantPast }
            return DotNetTicks.date(utc: DotNetTicks.utc(d))
        }
        return FileStamp(size: (a[.size] as? NSNumber)?.int64Value ?? 0,
                         modified: quantized(a[.modificationDate] as? Date),
                         created: quantized(a[.creationDate] as? Date))
    }

    /// A row for a set that could not be read at all.
    static func failed(path: String, error: String) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.error = error
        return e
    }

    static func build(path: String, stamp: FileStamp, env: LiveEnvironment, probe: ProbeCache) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.modified = stamp.modified
        e.created = stamp.created
        e.size = stamp.size
        e.isBackup = path.range(of: "/Backup/", options: .caseInsensitive) != nil
        e.projectName = e.projectNameFromPath

        let info = AlsFile.read(path: path)
        if let err = info.error { e.error = err; return e }

        e.creator = info.creator
        e.tempo = info.tempo
        e.key = info.key
        e.scaleRoot = info.scaleRoot
        e.scaleIndex = info.scaleIndex
        e.tracks = info.totalTracks
        applyPlugins(info.plugins, to: &e)
        applySamples(info.files, projectDir: e.directory, env: env, probe: probe, to: &e)
        return e
    }

    /// One and the same plugin occurs in a set many times over, and not every copy has a browser
    /// path. We take the first non-empty one, but a reliable source (VST3/AU) always beats a
    /// browser folder name. Sorted by name.
    static func applyPlugins(_ refs: [PluginRef], to e: inout SetEntry) {
        var best: [String: PluginRef] = [:]
        for p in refs where !p.name.isEmpty {
            let k = p.name.lowercased()
            guard let cur = best[k] else { best[k] = p; continue }
            let better = (p.vendorConfident && !cur.vendorConfident)
                || (cur.uid.isEmpty && !p.uid.isEmpty)
                || (cur.manufacturer.isEmpty && !p.manufacturer.isEmpty)
            if better { best[k] = p }
        }
        let sorted = best.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        e.plugins = sorted.map(\.name)
        e.pluginVendors = sorted.map(\.manufacturer)
        e.pluginVendorConfident = sorted.map(\.vendorConfident)
        e.pluginUids = sorted.map(\.uid)
    }

    /// We count DISTINCT files rather than occurrences (one sample chopped into a hundred clips
    /// gives a hundred FileRefs), and only clip samples: Live embeds presets and racks into the
    /// set, and their FileRef is only a memory of provenance.
    static func applySamples(_ files: [FileRefInfo], projectDir: String, env: LiveEnvironment,
                             probe: ProbeCache, to e: inout SetEntry) {
        var seen = Set<String>()
        var missing = 0, real = 0
        var found: [String] = [], sizes: [Int64] = []
        for fr in files where fr.isSampleDependency {
            let rr = RefResolver.resolve(fr, projectDir: projectDir, env: env, probe: probe)
            if rr.status == .empty { continue }
            if !seen.insert(rr.resolvedPath.lowercased()).inserted { continue }
            real += 1
            if rr.status == .missing || rr.status == .missingPack { missing += 1; continue }
            found.append(rr.resolvedPath)
            sizes.append(fr.originalFileSize > 0 ? fr.originalFileSize : lengthOf(rr.resolvedPath))
        }
        e.totalRefs = real
        e.missingFiles = missing
        e.samples = found
        e.sampleSizes = sizes
    }

    private static func lengthOf(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
