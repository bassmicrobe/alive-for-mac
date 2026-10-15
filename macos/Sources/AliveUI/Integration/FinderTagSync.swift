// Mac-only (opt-in, setting `findertags`): writes a project's Alive tags to its folder as Finder
// tags. It merges and never replaces: the person's own Finder tags stay, and only tags Alive
// itself added earlier are removed again. What Alive added is remembered in `findertags.cfg` in
// the data folder (`dir<TAB>tag<TAB>tag`).
import Foundation
import AliveCore

struct FinderTagSync {
    let dataDir: String

    private var recordPath: String { AppHome.file("findertags.cfg", in: dataDir) }

    // MARK: record

    func loadRecord() -> [String: [String]] {
        var record: [String: [String]] = [:]
        for line in AppHome.readLines(recordPath) ?? [] {
            guard !line.hasPrefix("#") else { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            record[fields[0]] = Array(fields.dropFirst()).filter { !$0.isEmpty }
        }
        return record
    }

    private func saveRecord(_ record: [String: [String]]) {
        var lines = ["# Alive - Finder tags that Alive added itself (so only these are ever removed)"]
        for dir in record.keys.sorted() {
            guard let tags = record[dir], !tags.isEmpty else { continue }
            lines.append(([dir] + tags).joined(separator: "\t"))
        }
        do { try AppHome.writeAtomically(lines.joined(separator: "\n") + "\n", to: recordPath) }
        catch { Diag.fail("findertags.cfg write", error) }
    }

    // MARK: merge

    /// A Finder tag name can carry its colour after a line break ("Red\n6"); the name is the first part.
    static func bareName(_ tag: String) -> String {
        tag.components(separatedBy: .newlines).first ?? tag
    }

    private static func contains(_ list: [String], _ tag: String) -> Bool {
        list.contains { bareName($0).caseInsensitiveCompare(bareName(tag)) == .orderedSame }
    }

    /// Pure merge. `current` are the folder's Finder tags, `desired` Alive's tags for it, `recorded`
    /// what Alive added before. Returns the tags to write and the tags Alive now owns.
    static func merge(current: [String], desired: [String], recorded: [String])
        -> (tags: [String], owned: [String]) {
        // Only what Alive added and the person has since dropped from the project goes away.
        var result = current.filter { tag in
            !(contains(recorded, tag) && !contains(desired, tag))
        }
        var owned: [String] = []
        for tag in desired {
            if contains(result, tag) {
                // Present: Alive's own only if it put it there; a tag the person had stays theirs.
                if contains(recorded, tag), !contains(owned, tag) { owned.append(tag) }
            } else {
                result.append(tag)
                owned.append(tag)
            }
        }
        return (result, owned)
    }

    // MARK: apply

    /// Brings the Finder tags of every folder in `desired` (folder -> Alive tags) in line, plus the
    /// folders Alive wrote to earlier. Keep ownership while a folder is unavailable: an external
    /// volume can return later with the tags Alive added still present. Returns how many folders
    /// were changed.
    @discardableResult
    func sync(desired: [String: [String]], shouldContinue: () -> Bool = { true }) -> Int {
        let previousRecord = loadRecord()
        var record = previousRecord
        var changed = 0
        for dir in Set(desired.keys).union(record.keys).sorted() {
            // Switched off or superseded meanwhile: stop before the next write. What was written
            // so far is still recorded below, so ownership stays accurate.
            guard shouldContinue() else { break }
            let wanted = (desired[dir] ?? []).map(Self.clean).filter { !$0.isEmpty }
            let recorded = record[dir] ?? []
            if wanted.isEmpty && recorded.isEmpty { continue }
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            do {
                let current = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                let merged = Self.merge(current: current, desired: wanted, recorded: recorded)
                if merged.tags != current {
                    // NSURL: the URLResourceValues setter exists only on macOS 26.
                    try (url as NSURL).setResourceValue(merged.tags, forKey: .tagNamesKey)
                    changed += 1
                }
                record[dir] = merged.owned.isEmpty ? nil : merged.owned
            } catch {
                Diag.fail("finder tags \(dir)", error)
            }
        }
        if record != previousRecord { saveRecord(record) }
        return changed
    }

    /// Tags go through a tab-separated file and a Finder name: no line breaks or tabs.
    private static func clean(_ tag: String) -> String {
        tag.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Decides whether queued Finder-tag work may still write. Main-actor code changes it
/// synchronously (`begin` / `disable`); the worker reads it before every folder.
final class FinderTagGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var enabled = false

    /// A new request supersedes every earlier one. nil while switched off.
    func begin() -> Int? {
        lock.withLock {
            guard enabled else { return nil }
            generation += 1
            return generation
        }
    }

    func enable() { lock.withLock { enabled = true } }

    /// Invalidates everything queued or running.
    func disable() { lock.withLock { enabled = false; generation += 1 } }

    func isCurrent(_ ticket: Int) -> Bool { lock.withLock { enabled && generation == ticket } }
}

/// The only writer of Finder tags and `findertags.cfg`: requests run one after another, and one
/// whose ticket is no longer current is dropped.
actor FinderTagWorker {
    private let sync: FinderTagSync
    nonisolated let gate: FinderTagGate

    init(dataDir: String, gate: FinderTagGate = FinderTagGate()) {
        sync = FinderTagSync(dataDir: dataDir)
        self.gate = gate
    }

    @discardableResult
    func run(desired: [String: [String]], ticket: Int) -> Int {
        let gate = gate
        guard gate.isCurrent(ticket) else { return 0 }
        return sync.sync(desired: desired, shouldContinue: { gate.isCurrent(ticket) })
    }
}
