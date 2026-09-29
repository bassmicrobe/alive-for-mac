// Port of src/RescueSession.cs (RescueProbe): probe copies of a set — the name, the journal and
// the cleanup.
import Foundation

/// A probe is placed NEXT TO the original rather than in a temporary folder, and that is not
/// laziness. Live measures relative sample references from the folder the .als itself lies in;
/// carry the copy off to /tmp and Live will honestly report that it has lost every file of the
/// project. Such a probe would be checking not the plugins but our own crookedness.
///
/// The journal (`probes.txt` in the data folder) lists the probes on disk right now, so they can
/// be removed after a crash.
public enum RescueProbe {
    /// The same constant `FolderScan` filters the catalog by.
    public static var suffix: String { FolderScan.probeSuffix }

    public static func journalPath(dir: String) -> String { AppHome.file("probes.txt", in: dir) }

    public static func isProbe(_ path: String) -> Bool {
        !path.isEmpty && path.lowercased().hasSuffix(suffix)
    }

    /// `<set folder>/<set name>.alive-probe.als`
    public static func path(for set: SetEntry) -> String {
        (set.directory as NSString).appendingPathComponent(set.name + suffix)
    }

    /// The path a probe for this set gets: `<name>.alive-probe.als`, or — when something already
    /// lies there (somebody's own file, or another running probe) — `<name> (2).alive-probe.als`
    /// and so on. Still ends in the probe suffix, so the catalog filter and the journal rules
    /// treat it alike.
    public static func freePath(for set: SetEntry) -> String {
        let first = path(for: set)
        if !exists(first) { return first }
        for i in 2..<1000 {
            let p = (set.directory as NSString).appendingPathComponent("\(set.name) (\(i))" + suffix)
            if !exists(p) { return p }
        }
        return first          // the exclusive create then fails cleanly instead of overwriting
    }

    /// `lstat`, so a dangling symlink counts as "something is there" too.
    private static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    /// Whether `path` is something this program may delete as a probe: an absolute path with
    /// the probe suffix that is a plain file (not a directory, not a link) which is empty or
    /// starts like a gzip / XML document. The journal is a text file that lies in the open and
    /// will one day be edited by hand; deleting what it names must not be able to go further.
    static func isDeletableProbe(_ path: String) -> Bool {
        guard isProbe(path), path.hasPrefix("/") else { return false }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return false }
        if st.st_size == 0 { return true }
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 5), head.count >= 2 else { return false }
        let bytes = [UInt8](head)
        return (bytes[0] == 0x1F && bytes[1] == 0x8B) || bytes == Array("<?xml".utf8)
    }

    /// Removes probes left over from the previous run. The program crashes rarely, but a probe is
    /// an .als inside somebody else's project folder, and it cannot be left there for good: one
    /// day a person opens it instead of their own set and cannot work out why half of it has no
    /// plugins. Called at launch, before the first scan. Returns how many files were removed.
    @discardableResult
    public static func cleanupStale(dir: String) -> Int {
        let listed = readJournal(dir: dir)
        guard !listed.isEmpty else { return 0 }
        var gone = 0
        var stillThere: [String] = []
        for p in listed {
            // Only what really is a probe is deleted: the journal lies there in the open and
            // will one day be edited by hand.
            guard isProbe(p) else { continue }
            guard exists(p) else { continue }           // already gone: strike it from the journal
            guard isDeletableProbe(p) else {
                Diag.warn("rescue: journal entry is not a probe file, left alone: \(p)")
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: p); gone += 1
            } catch {
                Diag.fail("rescue: cleanup \(p)", error)
                stillThere.append(p)                     // keep it: the next launch tries again
            }
        }
        writeJournal(stillThere, dir: dir)
        if gone > 0 { Diag.info("rescue: removed \(gone) stale probe(s)") }
        return gone
    }

    public static func remember(_ probe: String, dir: String) {
        var all = readJournal(dir: dir)
        if all.contains(where: { $0.caseInsensitiveCompare(probe) == .orderedSame }) { return }
        all.append(probe)
        writeJournal(all, dir: dir)
    }

    public static func forget(_ probe: String, dir: String) {
        let all = readJournal(dir: dir)
        let kept = all.filter { $0.caseInsensitiveCompare(probe) != .orderedSame }
        if kept.count != all.count { writeJournal(kept, dir: dir) }
    }

    /// Deletes a probe and strikes it from the journal. Quietly: tidying litter is no reason for
    /// an error window. Only what has really gone is struck: Live itself may have held the file
    /// open, and then only the next run can remove it — on the strength of this very record.
    public static func drop(_ probe: String, dir: String) {
        guard !probe.isEmpty, isProbe(probe) else { return }
        if exists(probe) {
            guard isDeletableProbe(probe) else {
                Diag.warn("rescue: not removing \(probe): not a probe file")
                forget(probe, dir: dir)
                return
            }
            do { try FileManager.default.removeItem(atPath: probe) } catch { Diag.fail("rescue: drop \(probe)", error) }
        }
        if !exists(probe) { forget(probe, dir: dir) }
    }

    /// Strikes a probe from the journal when there is nothing on disk under that name; never
    /// touches a file (used when creating the probe failed, and the name may be somebody's).
    public static func forgetIfGone(_ probe: String, dir: String) {
        if !exists(probe) { forget(probe, dir: dir) }
    }

    public static func journal(dir: String) -> [String] { readJournal(dir: dir) }

    private static func readJournal(dir: String) -> [String] {
        (AppHome.readLines(journalPath(dir: dir)) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func writeJournal(_ all: [String], dir: String) {
        do {
            try AppHome.writeAtomically(all.map { $0 + "\n" }.joined(), to: journalPath(dir: dir))
        } catch {
            Diag.fail("rescue: write journal", error)
        }
    }
}
