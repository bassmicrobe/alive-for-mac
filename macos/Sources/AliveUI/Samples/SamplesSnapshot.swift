// Mac-only: everything the Samples list derives from the library, worked out off the main actor and
// handed over as one immutable value. Nothing in `SamplesModel`'s getters computes any more: they
// read the last published snapshot, and a change of the inputs starts a new build.
import Foundation
import AliveCore

/// The inputs a snapshot was built from. Two equal keys mean two equal snapshots.
struct SamplesSnapshotKey: Equatable, Sendable {
    var indexGeneration: Int
    var catalogRevision: Int
    var lens: SampleLens
    var sort: SampleSort
    var openRevision: Int
    var query: String
    /// Duplicates are looked for only when the Duplicates lens, a Copies column, a sort by copies
    /// or a panel asks for them.
    var wantsCopies: Bool
}

struct SamplesSnapshot: Sendable {
    var key: SamplesSnapshotKey
    var usage: SampleUsage
    /// nil: not asked for by this key.
    var copies: SampleCopies?
    var listing: SampleListing
    /// Lower-cased names, kept for the next search over the same index.
    fileprivate var nameKeys: SampleNameKeys?
}

/// What `SamplesModel` hands to a build; all value types, safe to send.
struct SamplesSnapshotInput: Sendable {
    var key: SamplesSnapshotKey
    var index: SampleIndex
    var sets: [SetEntry]
    var open: Set<String>
    /// The snapshot shown so far: whatever it already holds for the same index or sets is reused.
    var previous: SamplesSnapshot?
}

enum SamplesSnapshotBuilder {
    /// nil when `isCancelled` turned true on the way.
    static func build(_ input: SamplesSnapshotInput, isCancelled: () -> Bool) -> SamplesSnapshot? {
        let key = input.key
        let prev = input.previous
        let sameIndex = prev?.key.indexGeneration == key.indexGeneration

        let usage: SampleUsage
        if let prev, sameIndex, prev.key.catalogRevision == key.catalogRevision {
            usage = prev.usage
        } else {
            usage = SampleUsage.compute(index: input.index, sets: input.sets, isCancelled: isCancelled)
        }
        if isCancelled() { return nil }

        // Found when something asks; once found for an index they are kept for it.
        var copies: SampleCopies? = sameIndex ? prev?.copies : nil
        if key.wantsCopies, copies == nil { copies = SampleCopies.find(in: input.index, isCancelled: isCancelled) }
        if isCancelled() { return nil }

        var keys: SampleNameKeys?
        if sameIndex, let k = prev?.nameKeys {
            keys = k
        } else if !key.query.trimmingCharacters(in: .whitespaces).isEmpty {
            keys = SampleNameKeys(input.index)
        }
        if isCancelled() { return nil }

        let listing = SampleLister.listing(index: input.index, usage: usage, copies: copies ?? .empty, lens: key.lens,
                                           sort: key.sort, open: input.open, query: key.query, keys: keys,
                                           isCancelled: isCancelled)
        if isCancelled() { return nil }
        return SamplesSnapshot(key: key, usage: usage, copies: copies, listing: listing, nameKeys: keys)
    }
}

/// What the folder panel shows below its numbers, worked out once per folder and snapshot instead
/// of on every evaluation of the panel's body.
struct SampleFolderSummary: Sendable {
    /// The used samples of the subtree, most used first (the panel shows the top ten).
    var used: [Int] = []
    var months = SampleMonths.empty
    /// The newest set of every project that uses something in the folder, newest first.
    var projects: [SetEntry] = []

    static func make(folder: Int, index: SampleIndex, usage: SampleUsage) -> SampleFolderSummary {
        let used = usage.usedUnder(folder, in: index)
        // A set that uses many of the samples is still one set: count it once.
        var distinct: [String: SetEntry] = [:]
        for f in used {
            for s in usage.of(file: f)?.sets ?? [] { distinct[s.path] = s }
        }
        let sets = Array(distinct.values)
        return SampleFolderSummary(used: used, months: SampleMonths.count(sets), projects: SampleUsage.newest(sets))
    }
}
