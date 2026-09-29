// Port of src/PluginInventory.cs (LoadFrom, Parse, ParseScannerLog, UidOf, VersionFolders).
//
// Live keeps its plugin list in `PluginScanDb.txt` (three CSV-ish tables: modules, plugins) and
// writes a cumulative `PluginScanner.txt` log with one "found" block per plugin. Windows keeps
// both in `Preferences/`; the Mac Live 11 keeps only the log, and directly in the version folder.
// Neither is required here: bundle scanning is the primary source (PluginBundleScanner).
import Foundation

/// Answers "is there a file at this path" for a whole load: the scanner log is cumulative and one
/// plugin occurs in it dozens of times, so each path is asked about once. The cache lives for one
/// load — otherwise a plugin installed while the program ran would not show up on "rescan".
final class PathExistsCache {
    private var known: [String: Bool] = [:]

    func exists(_ path: String) -> Bool {
        if path.isEmpty { return false }
        if let hit = known[path] { return hit }
        let now = FileManager.default.fileExists(atPath: path)
        known[path] = now
        return now
    }
}

struct LiveScanRecords {
    var plugins: [InstalledPlugin] = []
    var sourcePath = ""
    var scanned = Date.distantPast
}

enum PluginScanDb {
    // MARK: Live's version folders

    /// The version folders under `~/Library/Preferences/Ableton` ("Live 11.3.35"), the one that
    /// wrote its plugin files last first. A folder counts when it has Live's preferences; betas
    /// and localised builds name the folder differently, so if the "Live *" mask finds nothing
    /// every subfolder is looked at.
    static func versionFolders(root: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        func dirs(_ pick: (String) -> Bool) -> [String] {
            names.filter(pick).map { root + "/" + $0 }.filter { isLiveInstall($0) }
        }
        var all = dirs { $0.hasPrefix("Live ") }
        if all.isEmpty { all = dirs { !$0.hasPrefix(".") } }
        let touched = Dictionary(uniqueKeysWithValues: all.map { ($0, lastTouched($0)) })
        return all.sorted {
            let a = touched[$0] ?? .distantPast, b = touched[$1] ?? .distantPast
            return a != b ? a > b : $0.localizedStandardCompare($1) == .orderedDescending
        }
    }

    /// Where Live puts its plugin files: the Mac keeps them in the version folder, Windows in a
    /// `Preferences` subfolder.
    static func fileCandidates(in versionDir: String, _ name: String) -> [String] {
        [versionDir + "/" + name, versionDir + "/Preferences/" + name]
    }

    private static func isLiveInstall(_ dir: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return false }
        if fm.fileExists(atPath: dir + "/Preferences", isDirectory: &isDir), isDir.boolValue { return true }
        return ["Preferences.cfg", "Library.cfg", "PluginScanner.txt", "PluginScanDb.txt"]
            .contains { fm.fileExists(atPath: dir + "/" + $0) }
    }

    private static func lastTouched(_ dir: String) -> Date {
        var t = Date.distantPast
        for name in ["PluginScanDb.txt", "PluginScanner.txt"] {
            for f in fileCandidates(in: dir, name) {
                if let d = (try? FileManager.default.attributesOfItem(atPath: f))?[.modificationDate] as? Date, d > t { t = d }
            }
        }
        return t
    }

    // MARK: one install

    /// The database and the scanner log of one Live install.
    static func read(versionDir: String, paths: PathExistsCache) -> LiveScanRecords {
        var rec = LiveScanRecords()
        let fm = FileManager.default

        if let db = fileCandidates(in: versionDir, "PluginScanDb.txt").first(where: fm.fileExists(atPath:)) {
            if let lines = readLines(db) {
                rec.sourcePath = db
                rec.scanned = modified(db)
                rec.plugins = parseDb(lines, paths: paths)
            } else {
                Diag.warn("plugins: cannot read \(db)")
            }
        }

        // PluginScanDb.txt is a snapshot Live does not rewrite after every scan: a plugin was
        // found by the scanner half an hour after the database's last entry and never got into
        // it. The log is written on every scan and holds the same device-class-ids — and for
        // some installs (the Mac's) it exists while the database never does.
        if let log = fileCandidates(in: versionDir, "PluginScanner.txt").first(where: fm.fileExists(atPath:)) {
            if let lines = readLines(log) {
                let known = Set(rec.plugins.map { $0.uid.lowercased() })
                rec.plugins.append(contentsOf: parseScannerLog(lines, known: known, paths: paths))
                rec.scanned = max(rec.scanned, modified(log))
                if rec.sourcePath.isEmpty { rec.sourcePath = log }
            } else {
                Diag.warn("plugins: cannot read \(log)")
            }
        }
        return rec
    }

    private static func modified(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
    }

    private static func readLines(_ path: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        // Live writes UTF-8; a stray invalid byte must not lose the whole file.
        return String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
    }

    // MARK: the scanner log

    /// A "VST3: found: Name" block followed by indented fields. The log is cumulative and
    /// remembers plugins removed long ago, so only records whose file is on disk right now are
    /// taken. What the database already knows is left alone: there it carries an "enabled" flag.
    static func parseScannerLog(_ lines: [String], known: Set<String>, paths: PathExistsCache) -> [InstalledPlugin] {
        var found: [String: InstalledPlugin] = [:]      // the last record wins: the vendor and
        var order: [String] = []                        // the version may change on an update
        var cur: InstalledPlugin?
        var curDevice: String?

        func flush() {
            defer { cur = nil; curDevice = nil }
            guard var p = cur, let dev = curDevice, !dev.isEmpty, !p.name.isEmpty else { return }
            p.uid = uid(ofDevice: dev, kind: p.kind)
            guard !p.uid.isEmpty, !p.path.isEmpty, paths.exists(p.path) else { return }
            if p.category.isEmpty { p.category = category(ofDevice: dev) }
            let key = p.uid.lowercased()
            if found[key] == nil { order.append(key) }
            found[key] = p
        }

        for line in lines {
            if let (kind, name) = foundHeader(line) {
                flush()
                var p = InstalledPlugin()
                p.kind = kind
                p.name = name
                cur = p
                continue
            }
            // The fields of a block are indented; a line with no indent ends the block.
            guard cur != nil else { continue }
            guard let first = line.first, first == " " || first == "\t" else { flush(); continue }

            let t = line.trimmingCharacters(in: .whitespaces)
            if let v = value(t, "vendor: ") { cur?.vendor = v }
            else if let v = value(t, "version: ") { cur?.version = v }
            else if let v = value(t, "subCategories: ") { cur?.category = v }
            else if let v = value(t, "device-class-id: ") { curDevice = v }
            else if let v = value(t, "path: ") { cur?.path = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        flush()
        return order.compactMap { known.contains($0) ? nil : found[$0] }
    }

    private static func value(_ line: String, _ key: String) -> String? {
        line.hasPrefix(key) ? String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces) : nil
    }

    private static let headers: [(marker: String, kind: PluginKind)] = [
        ("info: VST3: found: ", .vst3), ("info: VST2: found: ", .vst2), ("info: AU: found: ", .audioUnit),
    ]

    private static func foundHeader(_ line: String) -> (PluginKind, String)? {
        for h in headers {
            if let r = line.range(of: h.marker) {
                return (h.kind, String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    // MARK: the database

    /// PluginScanDb.txt: two tables introduced by "Logging plugins information about … start".
    static func parseDb(_ lines: [String], paths: PathExistsCache) -> [InstalledPlugin] {
        var modulePath: [String: String] = [:]      // ModuleId -> file path, from the modules table
        var moduleOk: [String: Bool] = [:]
        var out: [InstalledPlugin] = []

        var section = 0                             // 1 — modules, 2 — plugins
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("Logging plugins information about plugin modules start") { section = 1; continue }
            if line.hasPrefix("Logging plugins information about all plugins start") { section = 2; continue }
            if line.hasPrefix("Logging plugins information about"), line.contains(" end ") { section = 0; continue }
            if section == 0 || line.hasPrefix("ModuleId,") || line.hasPrefix("PluginId,") { continue }

            let f = splitCsv(line)
            if section == 1, f.count >= 5 {
                modulePath[f[0]] = f[1]
                moduleOk[f[0]] = f[4].caseInsensitiveCompare("ok") == .orderedSame
            } else if section == 2, f.count >= 11 {
                if moduleOk[f[1]] == false { continue }     // «not-a-plugin»
                var p = InstalledPlugin()
                p.name = f[3]; p.vendor = f[4]; p.version = f[5]; p.category = f[9]
                p.enabled = f[10] == "1"
                let dev = f[2]
                p.kind = dev.hasPrefix("device:vst3:") ? .vst3 : dev.hasPrefix("device:vst:") ? .vst2
                    : dev.hasPrefix("device:au") ? .audioUnit : .vst3
                p.uid = uid(ofDevice: dev, kind: p.kind)
                p.path = modulePath[f[1]] ?? ""
                if p.uid.isEmpty || p.name.isEmpty { continue }
                if p.category.isEmpty { p.category = category(ofDevice: dev) }
                // For VST3 the "file" is routinely a bundle folder, so fileExists (which accepts
                // both) is the right test.
                p.fileMissing = !p.path.isEmpty && !paths.exists(p.path)
                out.append(p)
            }
        }
        return out
    }

    // MARK: identifiers

    /// "device:vst3:audiofx:<guid>?n=…" -> "vst3:<guid>"; "device:vst:instr:<number>?n=…" ->
    /// "vst2:<number>"; an Audio Unit's device id ends in its three four-character codes.
    static func uid(ofDevice dev: String, kind: PluginKind) -> String {
        var s = dev
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        let parts = s.components(separatedBy: ":")
        guard parts.count >= 2, let id = parts.last, !id.isEmpty else { return "" }
        let prefix = InstalledPlugin.uidPrefix(of: kind)
        if kind == .audioUnit, parts.count >= 4, parts.suffix(3).allSatisfy({ $0.count == 4 }) {
            return "au:" + parts.suffix(3).joined(separator: ":").lowercased()
        }
        return prefix + ":" + id.lowercased()
    }

    /// The device's class segment ("audiofx", "instr", "midifx") as a category, for records that
    /// carry no sub-categories of their own.
    static func category(ofDevice dev: String) -> String {
        let parts = dev.components(separatedBy: ":")
        guard parts.count >= 4 else { return "" }
        switch parts[2].lowercased() {
        case "instr", "instrument": return "Instrument"
        case "audiofx": return "Fx"
        case "midifx": return "MIDI Effect"
        default: return ""
        }
    }

    /// A line of the form '1,"/…/x.vst3",3,1,ok,"…"' — the quotes are stripped.
    static func splitCsv(_ line: String) -> [String] {
        var res: [String] = []
        var cur = ""
        var quoted = false
        for c in line {
            if c == "\"" { quoted.toggle(); continue }
            if c == ",", !quoted { res.append(cur); cur = ""; continue }
            cur.append(c)
        }
        res.append(cur)
        return res
    }
}
