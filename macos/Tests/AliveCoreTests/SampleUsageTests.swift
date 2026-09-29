import XCTest
@testable import AliveCore

final class SampleUsageTests: XCTestCase {
    /// Lib/Drums/{kick,snare}.wav, Lib/Pads/{warm,cold}.wav, Lib/Dead/{a,b}.wav, Lib/Dead/Sub/c.wav
    private func library() -> (TempDir, String, SampleIndex) {
        let t = makeTemp("usage")
        let root = t.mkdir("Lib")
        for (i, n) in ["Drums/kick", "Drums/snare", "Pads/warm", "Pads/cold", "Dead/a", "Dead/b", "Dead/Sub/c"].enumerated() {
            SampleFixtures.put(SampleFixtures.wav(frames: 50 + i, seed: UInt8(i)), at: root + "/\(n).wav")
        }
        return (t, root, SampleIndex.build(roots: [root], disabled: []))
    }

    private func set(_ t: TempDir, _ path: String, samples: [(String, Int64)], modified: Double) -> SetEntry {
        var e = SetEntry()
        e.path = t.sub("Music/" + path)
        e.name = (path as NSString).lastPathComponent
        e.modified = Date(timeIntervalSince1970: modified)
        e.samples = samples.map(\.0)
        e.sampleSizes = samples.map(\.1)
        return e
    }

    private func fileIndex(_ idx: SampleIndex, _ name: String) -> Int { idx.files.firstIndex { $0.name == name }! }
    private func folderIndex(_ idx: SampleIndex, _ name: String) -> Int { idx.folders.firstIndex { $0.name == name }! }

    func testUsageIsCountedByProjectsNotByVersions() {
        let (t, root, idx) = library()
        let kick = root + "/Drums/kick.wav"
        let sets = [
            set(t, "Song Project/song v1.als", samples: [(kick, 0)], modified: 1_000),
            set(t, "Song Project/song v2.als", samples: [(kick, 0)], modified: 3_000),
            set(t, "Song Project/song v3.als", samples: [(kick, 0), (root + "/Pads/warm.wav", 0)], modified: 2_000),
            set(t, "Other Project/other.als", samples: [(kick, 0)], modified: 500),
        ]
        let u = SampleUsage.compute(index: idx, sets: sets)
        let k = u.of(file: fileIndex(idx, "kick.wav"))!
        XCTAssertEqual(k.sets.count, 4)
        XCTAssertEqual(k.projects, 2)
        XCTAssertEqual(k.lastUsed, Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(u.of(file: fileIndex(idx, "warm.wav"))?.projects, 1)
        XCTAssertNil(u.of(file: fileIndex(idx, "snare.wav")))

        // A folder's projects are the union over its subtree, not a sum.
        let drums = u.of(folder: folderIndex(idx, "Drums"))!
        XCTAssertEqual(drums.used, 1)
        XCTAssertEqual(drums.projects, 2)
        XCTAssertEqual(u.of(folder: 0)?.used, 2)
        XCTAssertEqual(u.of(folder: 0)?.projects, 2)
        XCTAssertNil(u.of(folder: folderIndex(idx, "Dead")))
        XCTAssertEqual(u.usedCount, 2)
        XCTAssertEqual(u.files(ofSet: sets[2].path).count, 2)
        XCTAssertEqual(u.files(ofSet: "/nope"), [])
    }

    func testACopyOutsideTheLibraryIsMatchedBySizeAndName() {
        let (t, root, idx) = library()
        let size = idx.files[fileIndex(idx, "snare.wav")].size
        let imported = t.sub("Music/Song Project/Samples/Imported/Snare.wav")
        let sets = [set(t, "Song Project/song.als", samples: [(imported, size), (imported.replacingOccurrences(of: "Snare", with: "other"), size)], modified: 1)]
        let u = SampleUsage.compute(index: idx, sets: sets)
        XCTAssertEqual(u.of(file: fileIndex(idx, "snare.wav"))?.projects, 1)
        XCTAssertEqual(u.usedCount, 1, "a namesake is required as well as the size")
        // No recorded size, no match.
        let none = SampleUsage.compute(index: idx, sets: [set(t, "S Project/s.als", samples: [(imported, 0)], modified: 1)])
        XCTAssertEqual(none.usedCount, 0)
        _ = root
    }

    func testPathsAreMatchedRegardlessOfCase() {
        let (t, root, idx) = library()
        let sets = [set(t, "S Project/s.als", samples: [(root.uppercased() + "/DRUMS/KICK.WAV", 0)], modified: 1)]
        XCTAssertEqual(SampleUsage.compute(index: idx, sets: sets).usedCount, 1)
    }

    func testEmptyInputsGiveNoUsage() {
        let (_, _, idx) = library()
        XCTAssertEqual(SampleUsage.compute(index: idx, sets: []).usedCount, 0)
        XCTAssertEqual(SampleUsage.compute(index: .empty, sets: [SetEntry()]).usedCount, 0)
    }

    func testNeverUsedListsOnlyTheTopmostUnusedFolders() {
        let (t, root, idx) = library()
        let sets = [set(t, "S Project/s.als", samples: [(root + "/Drums/kick.wav", 0), (root + "/Dead/Sub/c.wav", 0)], modified: 1)]
        let u = SampleUsage.compute(index: idx, sets: sets)
        // Dead is used (through Sub), so its unused samples are not a folder; Pads is untouched.
        XCTAssertEqual(u.neverUsed(in: idx).map { idx.folders[$0].name }, ["Pads"])

        let none = SampleUsage.compute(index: idx, sets: [set(t, "S Project/s.als", samples: [], modified: 1)])
        XCTAssertEqual(none.neverUsed(in: idx), [0], "nothing used: the whole root, once")
    }

    func testUsedUnderIsOrderedByProjectsThenRecencyThenName() {
        let (t, root, idx) = library()
        let sets = [
            set(t, "A Project/a.als", samples: [(root + "/Drums/kick.wav", 0), (root + "/Drums/snare.wav", 0)], modified: 100),
            set(t, "B Project/b.als", samples: [(root + "/Drums/snare.wav", 0)], modified: 50),
            set(t, "C Project/c.als", samples: [(root + "/Pads/warm.wav", 0), (root + "/Pads/cold.wav", 0)], modified: 200),
        ]
        let u = SampleUsage.compute(index: idx, sets: sets)
        XCTAssertEqual(u.usedUnder(0, in: idx).map { idx.files[$0].name }, ["snare.wav", "cold.wav", "warm.wav", "kick.wav"])
        XCTAssertEqual(u.usedUnder(folderIndex(idx, "Drums"), in: idx).map { idx.files[$0].name }, ["snare.wav", "kick.wav"])
        XCTAssertEqual(u.usedUnder(folderIndex(idx, "Dead"), in: idx), [])
    }

    func testNewestKeepsOneSetPerProject() {
        let t = makeTemp("usage")
        let a1 = set(t, "A Project/a1.als", samples: [], modified: 10)
        let a2 = set(t, "A Project/a2.als", samples: [], modified: 30)
        let b = set(t, "B Project/b.als", samples: [], modified: 20)
        XCTAssertEqual(SampleUsage.newest([a1, b, a2]).map(\.name), ["a2.als", "b.als"])
    }

    func testCopiesNeedEqualNameSizeAndContent() {
        let t = makeTemp("copies")
        let root = t.mkdir("Lib")
        let big = SampleFixtures.wav(frames: 4000, seed: 1)
        SampleFixtures.put(big, at: root + "/P1/loop.wav")
        SampleFixtures.put(big, at: root + "/P2/loop.wav")
        SampleFixtures.put(big, at: root + "/P3/Loop.wav")
        let small = SampleFixtures.wav(frames: 100, seed: 2)
        SampleFixtures.put(small, at: root + "/P1/hit.wav")
        SampleFixtures.put(small, at: root + "/P2/hit.wav")
        SampleFixtures.put(SampleFixtures.wav(frames: 100, seed: 3), at: root + "/P3/hit.wav")      // same size, other sound
        SampleFixtures.put(SampleFixtures.wav(frames: 100, seed: 9), at: root + "/P3/alone.wav")
        let idx = SampleIndex.build(roots: [root], disabled: [])
        let c = SampleCopies.find(in: idx)

        // The most wasted room first (loop: 2 extra copies of 8 KB), copies of one sound side by side.
        XCTAssertEqual(c.files.map { idx.files[$0].name.lowercased() }, ["loop.wav", "loop.wav", "loop.wav", "hit.wav", "hit.wav"])
        XCTAssertEqual(c.files.prefix(3).map { idx.folders[idx.files[$0].folder].name }, ["P1", "P2", "P3"])
        XCTAssertEqual(c.extraBytes, Int64(big.count) * 2 + Int64(small.count))

        let loop1 = c.files[0]
        XCTAssertEqual(c.copies(of: loop1), 2)
        XCTAssertEqual(c.others(of: loop1).count, 2)
        XCTAssertFalse(c.others(of: loop1).contains(loop1))
        let alone = idx.files.firstIndex { $0.name == "alone.wav" }!
        XCTAssertEqual(c.copies(of: alone), 0)
        XCTAssertEqual(c.others(of: alone), [])

        let p1 = idx.folders.firstIndex { $0.name == "P1" }!
        XCTAssertEqual(c.files(in: p1), 2)
        XCTAssertEqual(c.bytes(in: p1), Int64(big.count + small.count))
        XCTAssertEqual(c.files(in: 0), 5)
        XCTAssertEqual(SampleCopies.find(in: .empty).files, [])
    }

    func testFilesWithoutPrintAreNeverCopies() {
        var idx = SampleIndex()
        var root = SampleFolder(); root.path = "/lib"; root.name = "/lib"; root.files = [0, 1]; root.totalSamples = 2
        idx.folders = [root]; idx.roots = [0]
        var f = SampleFile(); f.name = "a.wav"; f.size = 10
        idx.files = [f, f]
        XCTAssertEqual(SampleCopies.find(in: idx).files, [])
    }
}
