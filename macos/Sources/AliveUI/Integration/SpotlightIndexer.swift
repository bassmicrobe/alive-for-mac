// Mac-only: keeps Spotlight's copy of the catalog in step with it. The system index is reached
// only through `SpotlightBackend`, so tests use a fake and never touch the real CSSearchableIndex.
// Work runs in an actor (off the main thread), incrementally: the previous snapshot (id +
// signature of what was indexed) is diffed against the current documents and only the
// difference is sent, in batches.
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import AliveCore

// MARK: - Backend

protocol SpotlightBackend: Sendable {
    func index(_ documents: [SpotlightDocument]) async throws
    func delete(ids: [String]) async throws
    func deleteAll() async throws
}

/// Does nothing: tests, and runs where the real index must stay untouched.
struct NullSpotlightBackend: SpotlightBackend {
    func index(_ documents: [SpotlightDocument]) async throws {}
    func delete(ids: [String]) async throws {}
    func deleteAll() async throws {}
}

/// The system's Core Spotlight index. Items live in one domain, so "delete everything" removes
/// exactly what Alive added.
struct CoreSpotlightBackend: SpotlightBackend {
    static let domain = "com.alive-for-mac.sets"

    func index(_ documents: [SpotlightDocument]) async throws {
        let items = documents.map { doc -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = doc.title
            attributes.displayName = doc.displayName
            attributes.contentDescription = doc.contentDescription
            attributes.keywords = doc.keywords
            attributes.contentModificationDate = doc.modified
            attributes.contentCreationDate = doc.created
            let item = CSSearchableItem(uniqueIdentifier: doc.id, domainIdentifier: Self.domain,
                                        attributeSet: attributes)
            item.expirationDate = .distantFuture      // the default is one month
            return item
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    func delete(ids: [String]) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids)
    }

    func deleteAll() async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
    }
}

// MARK: - Plan

/// What has to be sent to bring the index from `previous` (id -> signature) to `current`.
struct SpotlightPlan: Equatable {
    var upserts: [SpotlightDocument]
    var deletes: [String]

    var isEmpty: Bool { upserts.isEmpty && deletes.isEmpty }

    static func make(previous: [String: String], current: [SpotlightDocument]) -> SpotlightPlan {
        var seen = Set<String>()
        var upserts: [SpotlightDocument] = []
        for doc in current where seen.insert(doc.id).inserted {
            if previous[doc.id] != doc.signature { upserts.append(doc) }
        }
        let deletes = previous.keys.filter { !seen.contains($0) }.sorted()
        return SpotlightPlan(upserts: upserts, deletes: deletes)
    }
}

// MARK: - Snapshot file

/// `spotlight.snapshot` in the data folder: one `id<TAB>signature` line per indexed set.
struct SpotlightSnapshotFile {
    let path: String

    init(dir: String) { path = AppHome.file("spotlight.snapshot", in: dir) }

    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    func load() -> [String: String] {
        var map: [String: String] = [:]
        for line in AppHome.readLines(path) ?? [] {
            guard !line.hasPrefix("#"), let tab = line.firstIndex(of: "\t") else { continue }
            map[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        return map
    }

    func save(_ map: [String: String]) {
        var lines = ["# Alive - what has been given to Spotlight"]
        for key in map.keys.sorted() { lines.append("\(key)\t\(map[key] ?? "")") }
        do { try AppHome.writeAtomically(lines.joined(separator: "\n") + "\n", to: path) }
        catch { Diag.fail("spotlight.snapshot write", error) }
    }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}

// MARK: - Indexer

actor SpotlightIndexer {
    static let batchSize = 200

    private let backend: SpotlightBackend
    private let file: SpotlightSnapshotFile
    private var snapshot: [String: String]
    /// The domain was already emptied since the last `sync`: later "off" calls have nothing to do.
    private var clearedSinceSync = false

    init(dataDir: String, backend: SpotlightBackend) {
        self.backend = backend
        file = SpotlightSnapshotFile(dir: dataDir)
        snapshot = file.load()
    }

    /// Brings the index in line with `documents`.
    func sync(_ documents: [SpotlightDocument]) async {
        clearedSinceSync = false
        let plan = SpotlightPlan.make(previous: snapshot, current: documents)
        guard !plan.isEmpty else { return }
        do {
            for batch in plan.deletes.chunked(Self.batchSize) {
                try await backend.delete(ids: batch)
                batch.forEach { snapshot[$0] = nil }
            }
            for batch in plan.upserts.chunked(Self.batchSize) {
                try await backend.index(batch)
                batch.forEach { snapshot[$0.id] = $0.signature }
            }
        } catch {
            Diag.fail("spotlight index", error)
        }
        file.save(snapshot)
        Diag.info("spotlight: \(plan.upserts.count) indexed, \(plan.deletes.count) removed")
    }

    /// The toggle is off: removes everything Alive gave to Spotlight. It does not depend on the
    /// local snapshot (the data folder may have been deleted or switched, or Alive may have crashed
    /// between indexing and saving it), so the domain is deleted once per launch whenever the
    /// toggle is off; deleting an empty domain is harmless and touches nothing else.
    func removeEverything() async {
        guard !clearedSinceSync else { return }
        do {
            try await backend.deleteAll()
            snapshot = [:]
            file.remove()
            clearedSinceSync = true
            Diag.info("spotlight: index cleared")
        } catch {
            Diag.fail("spotlight clear", error)
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Continuation

/// The identifier Spotlight hands back when a result is opened (`CSSearchableItemActionType`).
enum SpotlightLink {
    static func path(activityType: String, userInfo: [AnyHashable: Any]?) -> String? {
        guard activityType == CSSearchableItemActionType,
              let id = userInfo?[CSSearchableItemActivityIdentifier] as? String, !id.isEmpty else { return nil }
        return id
    }
}
