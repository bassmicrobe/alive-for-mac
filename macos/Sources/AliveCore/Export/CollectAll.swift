// Port of src/CollectAll.cs — the plan and the run. Mac: .zip through `/usr/bin/ditto`.
import Foundation

public enum CollectError: Error, Equatable {
    case cancelled
    /// The folder or archive already exists — collecting never merges into or overwrites one.
    case destinationExists(String)
    case notEnoughSpace(needed: Int64, free: Int64)
    /// `ditto` failed; `output` is its stderr.
    case packFailed(status: Int32, output: String)
    /// The collected .als could not be written (or its FileRef numbering drifted).
    case setNotWritten(String)
    case io(String)
}

/// A file that could not be copied.
public struct CollectFailure: Equatable, Sendable {
    public var name: String
    public var path: String
    public var reason: String

    public init(name: String, path: String, reason: String) {
        self.name = name
        self.path = path
        self.reason = reason
    }
}

public struct CollectProgress: Equatable, Sendable {
    public enum Phase: Sendable { case copying, writingSet, packing }
    public var phase: Phase
    public var done = 0
    public var total = 0
    public var current = ""

    public init(phase: Phase, done: Int = 0, total: Int = 0, current: String = "") {
        self.phase = phase
        self.done = done
        self.total = total
        self.current = current
    }
}

public struct CollectResult: Equatable, Sendable {
    /// The folder, or the .zip.
    public var output = ""
    public var copiedFiles = 0
    public var copiedBytes: Int64 = 0
    /// Files that could not be copied — their references stay as they were in the original.
    public var failed: [CollectFailure] = []

    public init(output: String = "") { self.output = output }
}

/// Collecting a project into a portable folder or archive. The logic sits apart from the sheet.
///
/// The original is not touched: what is collected goes into a new folder, and the source .als is
/// opened read-only.
public enum CollectAll {
    static let importedDir = "Samples/Imported"
    static let devicesDir = "Devices"
    static let projectInfo = "Ableton Project Info"

    // MARK: planning

    /// Rows for the sheet: how many files / bytes each origin brings, before anything is copied.
    public static func groups(_ deps: [CollectDependency], _ opt: CollectOptions) -> [CollectGroup] {
        let order: [CollectOrigin] = [.inProject, .elsewhere, .otherProject, .userLibrary, .factoryPack]
        return order.map { origin in
            var g = CollectGroup(origin: origin)
            g.included = opt.wants(origin)
            for d in deps where d.origin == origin {
                g.files += 1
                g.bytes += d.size
            }
            return g
        }
    }

    /// The default destination: `<project folder>/<set name> Project_export`, and with a counter
    /// when taken. Next to the source, with no intermediate folder: an export is looked for where
    /// the project itself is. The name has to be free both as a folder and as an archive.
    public static func freeTarget(for set: SetEntry) -> String {
        let fm = FileManager.default
        for n in 1..<1000 {
            let name = set.name + " Project_export" + (n == 1 ? "" : " \(n)")
            let dir = (set.projectDir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: dir), !fm.fileExists(atPath: dir + ".zip") { return dir }
        }
        return (set.projectDir as NSString).appendingPathComponent(
            set.name + " Project_export \(Int(Date().timeIntervalSince1970))")
    }

    /// What will be done. `targetDir` is where the folder will be created (the archive is
    /// `targetDir + ".zip"`); nothing is created here.
    public static func plan(set: SetEntry, deps: [CollectDependency], options: CollectOptions,
                            targetDir: String? = nil) -> CollectPlan {
        var plan = CollectPlan()
        plan.targetDir = targetDir ?? freeTarget(for: set)
        plan.zip = options.toZip
        plan.groups = groups(deps, options)
        let setDir = set.directory

        // The first pass only stakes out the names of in-project files. Were it a single pass
        // together with handing out names to external ones, the order of dependencies (the
        // order of FileRefs in the document — chosen by the set's author) would decide who takes
        // "Samples/Imported/kick.wav" first, and an in-project file of the same name could stake
        // out that same path a second time; one copy would silently overwrite the other.
        var taken = Set<String>()
        for d in deps where d.origin == .inProject {
            if let rel = CollectScan.relative(root: setDir, path: d.path) { taken.insert(rel.lowercased()) }
        }

        for d in deps {
            if d.origin == .missing { plan.notFound.append(d); continue }
            if d.refusal != nil { plan.refused.append(d); continue }
            guard options.wants(d.origin) else { plan.skipped.append(d); continue }

            let rel: String
            if d.origin == .inProject {
                // We reproduce the set folder's structure, so the path in the copy is right as it
                // is — neither a rename nor an edit of the reference is needed.
                guard let r = CollectScan.relative(root: setDir, path: d.path) else {
                    plan.skipped.append(d)
                    continue
                }
                rel = r
            } else {
                rel = unique(&taken, (d.isDevice ? devicesDir : importedDir) + "/" + d.name)
                // The absolute path is completed at run time: it derives from the target, which
                // may still change between the plan and the collecting.
                let nr = NewRef(relativePath: rel, absolutePath: "", relativePathType: 3, clearPack: true)
                for i in d.refIndexes { plan.rewrites[i] = nr }
            }
            plan.dest[d.id] = rel
            plan.copy.append(d)
            plan.totalBytes += d.size
        }
        plan.freeBytes = freeSpace(near: plan.targetDir)
        plan.elsewhereFolders = Set(plan.copy.filter { $0.origin == .elsewhere }
            .map { ($0.realPath as NSString).deletingLastPathComponent }).sorted()
        if !plan.refused.isEmpty {
            let names = plan.refused.prefix(5).map(\.name).joined(separator: ", ")
            Diag.info("collect: \(plan.refused.count) file(s) refused (not media, hidden or private): \(names)")
        }
        return plan
    }

    /// Separates names that clashed: "kick.wav", "kick 2.wav", "kick 3.wav" (case-insensitive,
    /// like the default volume).
    static func unique(_ taken: inout Set<String>, _ rel: String) -> String {
        if taken.insert(rel.lowercased()).inserted { return rel }
        let ns = rel as NSString
        let dir = ns.deletingLastPathComponent
        let stem = (ns.lastPathComponent as NSString).deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension
        for n in 2..<100_000 {
            let name = "\(stem) \(n)\(ext)"
            let candidate = dir.isEmpty ? name : dir + "/" + name
            if taken.insert(candidate.lowercased()).inserted { return candidate }
        }
        let last = "\(dir)/\(stem) \(UUID().uuidString)\(ext)"
        taken.insert(last.lowercased())
        return last
    }

    /// Bytes available on the volume that will hold `path` (nearest existing ancestor).
    static func freeSpace(near path: String) -> Int64 {
        var dir = path
        while !FileManager.default.fileExists(atPath: dir), dir != "/", !dir.isEmpty {
            dir = (dir as NSString).deletingLastPathComponent
        }
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let v = try? URL(fileURLWithPath: dir).resourceValues(forKeys: keys) else { return Int64.max }
        if let big = v.volumeAvailableCapacityForImportantUsage, big > 0 { return big }
        return v.volumeAvailableCapacity.map(Int64.init) ?? Int64.max
    }

    // MARK: running

    /// Copies everything into the destination and writes the patched .als last: a collect cut
    /// short must not leave an export that looks finished. Throws `CollectError`; whatever this
    /// run created is removed on failure or cancel. `progress` is called on the calling thread.
    public static func run(plan: CollectPlan, set: SetEntry, info: AlsInfo,
                           progress: (CollectProgress) -> Void = { _ in },
                           isCancelled: () -> Bool = { false }) throws -> CollectResult {
        let fm = FileManager.default
        try validate(plan)

        // Archive mode stages the folder in a hidden folder beside the archive (the same volume,
        // so "twice the space" is literally what is needed) and removes it afterwards;
        // `--keepParent` gives the archive the same top folder as the folder mode would create.
        let stageParent = plan.zip
            ? ((plan.targetDir as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(".alive-collect-" + UUID().uuidString) : nil
        let root = stageParent.map { ($0 as NSString).appendingPathComponent((plan.targetDir as NSString).lastPathComponent) }
            ?? plan.targetDir
        var ok = false
        defer {
            if !ok {
                // Only what this run created: `validate` proved the destination did not exist.
                try? fm.removeItem(atPath: stageParent ?? plan.targetDir)
                if plan.zip { try? fm.removeItem(atPath: plan.zipPath) }
            } else if let stageParent {
                try? fm.removeItem(atPath: stageParent)
            }
        }

        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            var result = CollectResult(output: plan.outputPath)
            var rewrites = plan.rewrites
            try putProjectInfo(set, root: root)

            var done = 0
            for d in plan.copy {
                if isCancelled() { throw CollectError.cancelled }
                guard let rel = plan.dest[d.id] else { continue }
                do {
                    try recheck(d)
                    try put(d.path, to: (root as NSString).appendingPathComponent(rel))
                    result.copiedFiles += 1
                    result.copiedBytes += d.size
                } catch {
                    // A busy or over-long path is no reason to abandon the collecting: the person
                    // needs the other files. But keeping quiet will not do either — a copy
                    // without a sample looks whole and sounds wrong. The reference stays as it
                    // was in the original (like "sample not found") rather than point at a file
                    // that is not in the copy, and the loss goes into the result.
                    result.failed.append(CollectFailure(name: d.name, path: d.path,
                                                        reason: error.localizedDescription))
                    Diag.info("collect: cannot copy \(d.path): \(error.localizedDescription)")
                    for i in d.refIndexes { rewrites[i] = nil }
                    // A half-copied bundle is worse than a missing one.
                    try? fm.removeItem(atPath: (root as NSString).appendingPathComponent(rel))
                }
                done += 1
                progress(CollectProgress(phase: .copying, done: done, total: plan.copy.count, current: d.name))
            }

            // The absolute path is completed here: by now the target is final. In archive mode
            // the folder does not exist yet, and the path is right anyway — unpacking the
            // archive next to it gives exactly that folder.
            let absRoot = plan.targetDir.replacingOccurrences(of: "\\", with: "/")
            for (i, var nr) in rewrites {
                nr.absolutePath = absRoot + "/" + nr.relativePath
                rewrites[i] = nr
            }

            if isCancelled() { throw CollectError.cancelled }
            progress(CollectProgress(phase: .writingSet, done: done, total: plan.copy.count, current: set.name + ".als"))
            do {
                try AlsSamplePatch.rewrite(src: set.path,
                                           dst: (root as NSString).appendingPathComponent(set.name + ".als"),
                                           byIndex: rewrites, expectedRefCount: info.files.count,
                                           isCancelled: isCancelled)
            } catch is CancellationError {
                throw CollectError.cancelled
            } catch {
                throw CollectError.setNotWritten(String(describing: error))
            }

            if plan.zip {
                progress(CollectProgress(phase: .packing, done: done, total: plan.copy.count, current: ""))
                try pack(folder: root, into: plan.zipPath, isCancelled: isCancelled)
            }
            ok = true
            return result
        } catch let e as CollectError {
            throw e
        } catch {
            throw CollectError.io(error.localizedDescription)
        }
    }

    /// Nothing is ever merged into or overwritten: the destination must be new.
    static func validate(_ plan: CollectPlan) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: plan.targetDir) { throw CollectError.destinationExists(plan.targetDir) }
        if plan.zip, fm.fileExists(atPath: plan.zipPath) { throw CollectError.destinationExists(plan.zipPath) }
        if !plan.fits { throw CollectError.notEnoughSpace(needed: plan.zip ? plan.totalBytes * 2 : plan.totalBytes,
                                                          free: plan.freeBytes) }
    }

    /// Live decides a folder is a project by the presence of "Ableton Project Info". If the
    /// original has none (the set lies on its own), an empty one is made: Live writes its own
    /// into it on the first save.
    static func putProjectInfo(_ set: SetEntry, root: String) throws {
        let fm = FileManager.default
        let dst = (root as NSString).appendingPathComponent(projectInfo)
        let src = (set.projectDir as NSString).appendingPathComponent(projectInfo)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue,
              let names = try? fm.contentsOfDirectory(atPath: src), !names.isEmpty else {
            try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
            return
        }
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        do {
            for n in names where !n.hasPrefix(".") {
                try put((src as NSString).appendingPathComponent(n), to: (dst as NSString).appendingPathComponent(n), anyFolder: true)
            }
        } catch { Diag.info("collect: project info: \(error.localizedDescription)") }
    }

    /// The plan was made a moment ago; the file system may have moved since. What is copied
    /// must still be the file that was vetted: a link retargeted in between (to a private file)
    /// is refused rather than followed.
    static func recheck(_ d: CollectDependency) throws {
        guard !d.realPath.isEmpty, CollectSafety.realPath(d.path) == d.realPath else {
            throw CollectError.io("the file changed after it was checked")
        }
    }

    /// Copies a file or a bundle folder (.adg/.amxd) with everything inside. A symlink source is
    /// followed: a link in the export would dangle — but only to a plain file or a known
    /// bundle, never to a device node or a folder of something else. Never overwrites.
    static func put(_ src: String, to dst: String, anyFolder: Bool = false) throws {
        let fm = FileManager.default
        let real = CollectSafety.realPath(src) ?? URL(fileURLWithPath: src).resolvingSymlinksInPath().path
        var st = stat()
        guard stat(real, &st) == 0 else { throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: src]) }
        let ext = (real as NSString).pathExtension.lowercased()
        switch st.st_mode & S_IFMT {
        case S_IFREG: break
        case S_IFDIR where anyFolder || CollectSafety.bundleExtensions.contains(ext): break
        default: throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: src])
        }
        try fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fm.copyItem(atPath: real, toPath: dst)
    }

    /// `ditto -c -k --sequesterRsrc --keepParent <folder> <zip>` — Finder-compatible archive.
    static func pack(folder: String, into zip: String, isCancelled: () -> Bool) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // `--` ends the options: a folder named "-x…" must not be read as a flag.
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", "--", folder, zip]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { throw CollectError.packFailed(status: -1, output: error.localizedDescription) }

        // stderr is drained on a thread: a full pipe would stall ditto.
        var errData = Data()
        let reader = DispatchQueue(label: "collect.ditto.stderr")
        let group = DispatchGroup()
        group.enter()
        reader.async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning {
            if isCancelled() { p.terminate(); p.waitUntilExit(); group.wait(); throw CollectError.cancelled }
            Thread.sleep(forTimeInterval: 0.1)
        }
        group.wait()
        guard p.terminationStatus == 0 else {
            throw CollectError.packFailed(status: p.terminationStatus,
                                          output: String(decoding: errData, as: UTF8.self))
        }
    }
}
