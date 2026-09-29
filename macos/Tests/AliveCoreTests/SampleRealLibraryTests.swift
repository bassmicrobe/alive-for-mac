import XCTest
@testable import AliveCore

/// Set ALIVE_TEST_SAMPLES=/path/to/samples to walk a real library: no crash, sane numbers, the cache
/// round-trips. Reads only; prints the file count and the timings.
final class SampleRealLibraryTests: XCTestCase {
    func testWalkARealSampleLibrary() throws {
        guard let root = ProcessInfo.processInfo.environment["ALIVE_TEST_SAMPLES"], !root.isEmpty else {
            throw XCTSkip("ALIVE_TEST_SAMPLES not set")
        }
        func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

        var t = Date()
        let cold = SampleIndex.build(roots: [root], disabled: [])
        let coldMs = ms(t)
        t = Date()
        let warm = SampleIndex.build(roots: [root], disabled: [], previous: cold)
        let warmMs = ms(t)

        XCTAssertGreaterThan(cold.files.count, 0)
        XCTAssertEqual(cold.totalSamples, cold.files.count)
        XCTAssertEqual(warm.totalSamples, cold.totalSamples)
        XCTAssertEqual(cold.roots, [0])
        for (i, f) in cold.folders.enumerated() where i > 0 { XCTAssertLessThan(f.parent ?? Int.max, i) }
        let withPrint = cold.files.filter { $0.print != 0 }.count
        let silent = cold.files.filter(\.silent).count

        t = Date()
        let copies = SampleCopies.find(in: cold)
        let copiesMs = ms(t)
        t = Date()
        let usage = SampleUsage.compute(index: cold, sets: [])
        let usageMs = ms(t)
        t = Date()
        let listing = SampleLister.listing(index: cold, usage: usage, copies: copies, lens: .neverUsed, sort: SampleSort(),
                                           open: [], query: "")
        let listMs = ms(t)

        let dir = NSTemporaryDirectory() + "alive-sample-real-" + UUID().uuidString
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        t = Date()
        SampleCache.save(cold, dir: dir)
        let back = SampleCache.load(dir: dir)
        let cacheMs = ms(t)
        XCTAssertEqual(back.files.count, cold.files.count)
        XCTAssertEqual(back.folders.count, cold.folders.count)

        print("""
        SAMPLES \(root): \(cold.files.count) files in \(cold.folders.count) folders, \(cold.totalBytes / 1_048_576) MB;
        SAMPLES walk cold \(coldMs) ms, warm \(warmMs) ms; prints \(withPrint), silent AIFF \(silent), \
        copies \(copies.files.count) (\(copies.extraBytes / 1_048_576) MB extra) in \(copiesMs) ms;
        SAMPLES usage(empty) \(usageMs) ms, never-used list \(listing.rows.count) rows in \(listMs) ms, cache save+load \(cacheMs) ms
        """)
    }
}
