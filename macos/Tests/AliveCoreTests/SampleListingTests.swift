import XCTest
@testable import AliveCore

final class SampleListingTests: XCTestCase {
    private func build() -> (TempDir, String, SampleIndex) {
        let t = makeTemp("listing")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.wav(frames: 300, seed: 1), at: root + "/Drums/kick.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 200, seed: 2), at: root + "/Drums/Snare 2.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 200, seed: 3), at: root + "/Drums/Snare 10.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 1000, seed: 4), at: root + "/Pads/warm.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 5000, seed: 5), at: root + "/Dead/big.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 900, seed: 6), at: root + "/Dead/Deeper/big2.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 300, seed: 1), at: root + "/Pads/kick.wav")     // a copy of the kick
        return (t, root, SampleIndex.build(roots: [root], disabled: []))
    }

    private func list(_ idx: SampleIndex, usage: SampleUsage = .empty, copies: SampleCopies = .empty,
                      lens: SampleLens = .all, sort: SampleSort = SampleSort(), open: Set<String> = [],
                      query: String = "", cap: Int = 5000) -> SampleListing {
        SampleLister.listing(index: idx, usage: usage, copies: copies, lens: lens, sort: sort, open: open,
                             query: query, cap: cap)
    }

    private func names(_ l: SampleListing, _ idx: SampleIndex) -> [String] {
        l.rows.map { row in
            switch row.kind {
            case .folder(let f): return idx.folders[f].name
            case .file(let f): return idx.files[f].name
            }
        }
    }

    private func usage(_ t: TempDir, _ root: String, _ idx: SampleIndex, _ used: [String]) -> SampleUsage {
        var s = SetEntry()
        s.path = t.sub("Music/S Project/s.als")
        s.modified = Date(timeIntervalSince1970: 100)
        s.samples = used.map { root + "/" + $0 }
        return SampleUsage.compute(index: idx, sets: [s])
    }

    func testTreeShowsOnlyOpenFoldersWithNaturalOrder() {
        let (_, _, idx) = build()
        XCTAssertEqual(names(list(idx), idx), [idx.folders[0].name])
        let opened = SampleLister.ancestors(of: 0, in: idx)
        let l = list(idx, open: opened)
        XCTAssertEqual(names(l, idx), [idx.folders[0].name, "Dead", "Drums", "Pads"])
        XCTAssertEqual(l.rows.map(\.depth), [0, 1, 1, 1])
        XCTAssertFalse(l.isFlat)

        let drums = idx.folders.firstIndex { $0.name == "Drums" }!
        let deeper = list(idx, open: opened.union(SampleLister.ancestors(of: drums, in: idx)))
        XCTAssertEqual(names(deeper, idx), [idx.folders[0].name, "Dead", "Drums", "kick.wav", "Snare 2.wav", "Snare 10.wav", "Pads"])
        XCTAssertEqual(deeper.rows[3].depth, 2)
        XCTAssertEqual(deeper.rows[3].id, idx.path(of: idx.folders[drums].files.first { idx.files[$0].name == "kick.wav" }!))
    }

    func testSortingAFolderColumnBothWaysWithNameAsTheTieBreak() {
        let (_, _, idx) = build()
        let open = SampleLister.ancestors(of: 0, in: idx)
        let bySize = list(idx, sort: SampleSort(column: .size, descending: true), open: open)
        XCTAssertEqual(names(bySize, idx).dropFirst(), ["Dead", "Pads", "Drums"])
        let asc = list(idx, sort: SampleSort(column: .samples, descending: false), open: open)
        // Drums 3 samples, Pads 2, Dead 2: ascending by count, ties by name.
        XCTAssertEqual(names(asc, idx).dropFirst(), ["Dead", "Pads", "Drums"])
        let desc = list(idx, sort: SampleSort(column: .samples, descending: true), open: open)
        XCTAssertEqual(names(desc, idx).dropFirst(), ["Drums", "Dead", "Pads"])
    }

    func testNeverUsedLensListsTheHeaviestFolderFirst() {
        let (t, root, idx) = build()
        let u = usage(t, root, idx, ["Drums/kick.wav"])
        let l = list(idx, usage: u, lens: .neverUsed)
        XCTAssertTrue(l.isFlat)
        XCTAssertEqual(names(l, idx), ["Dead", "Pads"])
        XCTAssertEqual(l.rows.map(\.depth), [0, 0])
        XCTAssertEqual(l.matches, 2)
    }

    func testMostUsedLensIsOrderedByUse() {
        let (t, root, idx) = build()
        var s2 = SetEntry(); s2.path = t.sub("Music/Two Project/t.als"); s2.modified = Date(timeIntervalSince1970: 200)
        s2.samples = [root + "/Pads/warm.wav"]
        var s1 = SetEntry(); s1.path = t.sub("Music/One Project/o.als"); s1.modified = Date(timeIntervalSince1970: 100)
        s1.samples = [root + "/Pads/warm.wav", root + "/Drums/kick.wav"]
        let u = SampleUsage.compute(index: idx, sets: [s1, s2])
        let l = list(idx, usage: u, lens: .mostUsed)
        XCTAssertEqual(names(l, idx), ["warm.wav", "kick.wav"])
        XCTAssertEqual(list(idx, usage: u, lens: .mostUsed, query: "KIC").rows.count, 1)
    }

    func testDuplicatesLensKeepsTheCopiesOrder() {
        let (_, _, idx) = build()
        let copies = SampleCopies.find(in: idx)
        let l = list(idx, copies: copies, lens: .duplicates)
        XCTAssertEqual(names(l, idx), ["kick.wav", "kick.wav"])
        XCTAssertEqual(l.rows.map(\.id), copies.files.map { idx.path(of: $0) })
    }

    func testSearchIsFlatCapsBeforeSortingAndSaysHowManyMatched() {
        let (_, _, idx) = build()
        let l = list(idx, query: "snare")
        XCTAssertEqual(names(l, idx), ["Snare 2.wav", "Snare 10.wav"])
        XCTAssertTrue(l.isFlat)
        // Folders match by name too; the roots do not.
        XCTAssertEqual(names(list(idx, query: "dee"), idx), ["Deeper"])
        XCTAssertEqual(names(list(idx, query: idx.folders[0].name), idx), [])

        let capped = list(idx, query: ".wav", cap: 3)
        XCTAssertEqual(capped.rows.count, 3)
        XCTAssertEqual(capped.matches, 7)
        XCTAssertTrue(capped.isCut)
        XCTAssertFalse(l.isCut)
        XCTAssertEqual(list(idx, query: "   ").isFlat, false)
    }

    func testFileColumnsSortByUseAndSize() {
        let (_, _, idx) = build()
        let bySize = list(idx, sort: SampleSort(column: .size, descending: true), query: ".wav")
        XCTAssertEqual(names(bySize, idx).prefix(2), ["big.wav", "warm.wav"])
    }

    func testColumnSpecRoundTripsAndRepairsItself() {
        let spec = SampleColumnSpec(spec: "Name,Location,Samples:140,Bogus,Size,Samples,Projects:-4")
        XCTAssertEqual(spec.order, [.name, .location, .samples, .size, .projects])
        XCTAssertEqual(spec.width(of: .samples), 140)
        XCTAssertEqual(spec.width(of: .projects), 120)
        XCTAssertEqual(spec.width(of: .name), 0)
        XCTAssertEqual(spec.spec, "Name,Location,Samples:140,Size,Projects")
        XCTAssertEqual(SampleColumnSpec(spec: spec.spec), spec)

        XCTAssertEqual(SampleColumnSpec(spec: "").order, SampleColumn.defaults)
        XCTAssertEqual(SampleColumnSpec(spec: "Size").order, [.name, .size])
        XCTAssertEqual(SampleColumnSpec(spec: "Name").order, SampleColumn.defaults, "the name alone is not a choice: defaults")
        XCTAssertEqual(SampleColumnSpec(spec: "Samples,Size").order, [.name, .samples, .size])
        XCTAssertEqual(SampleColumnSpec(spec: "name,LASTUSED").order, [.name, .lastUsed])
        // A width equal to the default is not written.
        XCTAssertEqual(SampleColumnSpec(spec: "Name,Size:130").spec, "Name,Size")
        XCTAssertEqual(SampleColumnSpec().spec, SampleColumn.defaults.map(\.rawValue).joined(separator: ","))
    }

    func testTogglingPutsAColumnAtItsPlaceInTheCatalog() {
        var spec = SampleColumnSpec(order: [.name, .size])
        spec = spec.toggling(.samples)
        XCTAssertEqual(spec.order, [.name, .samples, .size])
        spec = spec.toggling(.modified)
        XCTAssertEqual(spec.order, [.name, .samples, .modified, .size])
        XCTAssertEqual(spec.toggling(.size).order, [.name, .samples, .modified])
        XCTAssertEqual(spec.toggling(.name), spec)
    }

    func testTheViewDecidesSomeColumns() {
        let spec = SampleColumnSpec()
        XCTAssertFalse(spec.visible(lens: .all, isFlat: false).contains(.location))
        XCTAssertTrue(spec.visible(lens: .all, isFlat: true).contains(.location))
        let never = spec.visible(lens: .neverUsed, isFlat: true)
        XCTAssertEqual(never, [.name, .location, .samples, .created, .size])
        let dupes = spec.visible(lens: .duplicates, isFlat: true)
        XCTAssertTrue(dupes.contains(.copies))
        XCTAssertFalse(dupes.contains(.samples))
        XCTAssertFalse(dupes.contains(.used))
        XCTAssertEqual(SampleColumn.name.isPath, true)
        XCTAssertEqual(SampleColumn.size.isRightAligned, true)
    }
}
