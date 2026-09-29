// Port of SamplesTab.SampleCells / FolderRow / FileRow (src/SamplesTab.cs): what every row says in
// every column, and the counter over the list.
import Foundation
import AliveCore

/// Cell text for the rows of one snapshot (index, usage, copies).
struct SampleCells {
    let index: SampleIndex
    let usage: SampleUsage
    let copies: SampleCopies
    /// The sets have not been read yet: say "…" rather than "never".
    let unknown: Bool

    func text(_ column: SampleColumn, _ row: SampleRow) -> String {
        switch row.kind {
        case .folder(let d): return folderText(column, d)
        case .file(let f): return fileText(column, f)
        }
    }

    private func folderText(_ column: SampleColumn, _ d: Int) -> String {
        let folder = index.folders[d]
        let use = usage.of(folder: d)
        switch column {
        // A root's name is its whole path; the home folder is only ~.
        case .name: return folder.parent == nil ? (folder.path as NSString).abbreviatingWithTildeInPath : folder.name
        case .location: return index.location(of: folder.parent)
        case .samples: return SampleFormat.number(folder.totalSamples)
        case .used: return unknown ? SamplesStrings.usageUnknown.s : count(use?.used ?? 0)
        case .projects: return unknown ? SamplesStrings.usageUnknown.s : count(use?.projects ?? 0)
        case .lastUsed: return lastUsed(use?.lastUsed)
        case .size: return SampleFormat.megabytes(folder.totalBytes)
        // No copies is the ordinary case — an empty cell, not a dash in every row.
        case .copies: return blankZero(copies.files(in: d))
        case .created: return SampleFormat.day(folder.created)
        case .modified: return SampleFormat.day(folder.modified)
        }
    }

    private func fileText(_ column: SampleColumn, _ f: Int) -> String {
        let file = index.files[f]
        let use = usage.of(file: f)
        switch column {
        case .name: return file.name
        case .location: return index.location(of: file.folder)
        case .samples, .used: return ""
        case .projects: return unknown ? SamplesStrings.usageUnknown.s : count(use?.projects ?? 0)
        case .lastUsed: return lastUsed(use?.lastUsed)
        case .size: return SampleFormat.sampleSize(file.size)
        case .copies: return blankZero(copies.copies(of: f))
        case .created: return SampleFormat.day(file.created)
        case .modified: return SampleFormat.day(file.modified)
        }
    }

    private func count(_ n: Int) -> String { n > 0 ? SampleFormat.number(n) : "—" }
    private func blankZero(_ n: Int) -> String { n > 0 ? SampleFormat.number(n) : "" }

    private func lastUsed(_ date: Date?) -> String {
        if unknown { return SamplesStrings.usageUnknown.s }
        guard let date, date > .distantPast else { return SamplesStrings.never.s }
        return SampleFormat.day(date)
    }

    /// Whether a row is drawn quiet: nothing was ever taken from it.
    func isDim(_ row: SampleRow) -> Bool {
        guard !unknown else { return false }
        switch row.kind {
        case .folder(let d): return usage.of(folder: d) == nil
        case .file(let f): return usage.of(file: f) == nil
        }
    }
}

enum SampleCounter {
    /// The text over the list: the walk's progress, the library's size, or what a search or lens shows.
    static func text(isScanning: Bool, found: Int, listing: SampleListing, lens: SampleLens, hasQuery: Bool,
                     index: SampleIndex, copies: SampleCopies) -> String {
        if isScanning { return SamplesStrings.indexingCount.f(SampleFormat.number(found)) }
        if !listing.isFlat {
            let total = index.totalSamples
            let size = SampleFormat.megabytes(index.totalBytes)
            return total == 1 ? SamplesStrings.countOneSample.f(size)
                              : SamplesStrings.countSamples.f(SampleFormat.number(total), size)
        }
        let shown = SampleFormat.number(listing.rows.count)
        if listing.isCut { return SamplesStrings.countCut.f(shown, SampleFormat.number(listing.matches)) }
        // The lens of copies says what they cost — unless a search narrows it.
        if lens == .duplicates, !hasQuery, copies.extraBytes > 0 {
            return SamplesStrings.countDuplicates.f(shown, SampleFormat.megabytes(copies.extraBytes))
        }
        return CommonStrings.shownCount.f(listing.rows.count)
    }
}
