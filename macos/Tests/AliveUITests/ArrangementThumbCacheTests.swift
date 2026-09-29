import CoreGraphics
import XCTest
@testable import AliveCore
@testable import AliveUI

final class ArrangementThumbCacheTests: XCTestCase {
    private func makeSet(_ dir: HomeScratch, _ name: String = "a.als", bytes: String = "x") -> String {
        dir.write(name, bytes)
    }

    private func picture() throws -> CGImage {
        try XCTUnwrap(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 96, height: 54, options: .thumbnail))
    }

    func testMissingSetHasNoKey() {
        let cache = ThumbCache(dataDir: makeHomeScratch().path)
        XCTAssertNil(cache.keyFile(for: "/nope/none.als"))
        XCTAssertNil(cache.keyFile(for: ""))
        XCTAssertNil(cache.load("/nope/none.als"))
    }

    func testKeyDependsOnPathModificationTimeAndSize() throws {
        let t = makeHomeScratch()
        let cache = ThumbCache(dataDir: t.sub("data"))
        let a = makeSet(t, "a.als"), b = makeSet(t, "b.als")
        let keyA = try XCTUnwrap(cache.keyFile(for: a))
        XCTAssertEqual(keyA, cache.keyFile(for: a), "stable")
        XCTAssertNotEqual(keyA, cache.keyFile(for: b), "path")
        XCTAssertTrue(keyA.hasPrefix(t.path + "/data/thumbs/"))
        XCTAssertTrue(keyA.hasSuffix(".png"))
        t.setModified(a, Date(timeIntervalSince1970: 1_000_000))
        let touched = try XCTUnwrap(cache.keyFile(for: a))
        XCTAssertNotEqual(keyA, touched, "modification time")
        t.write("a.als", "longer content")
        t.setModified(a, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertNotEqual(touched, cache.keyFile(for: a), "size")
    }

    func testSaveThenLoadRoundTripsAcrossInstances() throws {
        let t = makeHomeScratch()
        let set = makeSet(t)
        ThumbCache(dataDir: t.sub("d")).save(set, image: try picture())
        // A fresh instance has an empty memory cache: this reads the PNG back.
        guard case .image(let loaded)? = ThumbCache(dataDir: t.sub("d")).load(set) else { return XCTFail("no picture") }
        XCTAssertEqual(loaded.cgImage.width, 96)
        XCTAssertEqual(loaded.cgImage.height, 54)
    }

    func testEmptyMarkIsRemembered() {
        let t = makeHomeScratch()
        let set = makeSet(t)
        ThumbCache(dataDir: t.sub("d")).save(set, image: nil)
        guard case .empty? = ThumbCache(dataDir: t.sub("d")).load(set) else { return XCTFail("empty mark lost") }
    }

    func testResavedSetInvalidatesTheEntry() throws {
        let t = makeHomeScratch()
        let set = makeSet(t)
        let cache = ThumbCache(dataDir: t.sub("d"))
        cache.save(set, image: try picture())
        XCTAssertTrue(cache.has(set))
        t.setModified(set, Date(timeIntervalSinceNow: 3600))
        XCTAssertFalse(cache.has(set))
        XCTAssertNil(cache.load(set))
    }

    func testCorruptEntryIsDroppedSoItGetsRedrawn() throws {
        let t = makeHomeScratch()
        let set = makeSet(t)
        let cache = ThumbCache(dataDir: t.sub("d"))
        cache.save(set, image: try picture())
        let file = try XCTUnwrap(cache.keyFile(for: set))
        try Data("not a png".utf8).write(to: URL(fileURLWithPath: file))
        XCTAssertNil(ThumbCache(dataDir: t.sub("d")).load(set))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file))
    }

    func testMemoryHitNeedsNoDisk() throws {
        let t = makeHomeScratch()
        let set = makeSet(t)
        let cache = ThumbCache(dataDir: t.sub("d"))
        XCTAssertNil(cache.loadFromMemory(set))
        cache.save(set, image: try picture())
        XCTAssertNotNil(cache.loadFromMemory(set))
        XCTAssertNil(ThumbCache(dataDir: t.sub("d")).loadFromMemory(set))
    }

    func testSweepKeepsTheNewest() throws {
        let t = makeHomeScratch()
        let cache = ThumbCache(dataDir: t.sub("d"))
        try FileManager.default.createDirectory(atPath: cache.dir, withIntermediateDirectories: true)
        for i in 0..<6 {
            let p = cache.dir + "/\(i).png"
            FileManager.default.createFile(atPath: p, contents: Data([1]))
            t.setModified(p, Date(timeIntervalSince1970: Double(1000 + i)))
        }
        XCTAssertEqual(cache.sweep(keeping: 4), 2)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: cache.dir))
        XCTAssertEqual(left, ["2.png", "3.png", "4.png", "5.png"])
        XCTAssertEqual(cache.sweep(keeping: 4), 0)
    }
}

final class ArrangementThumbnailPipelineTests: XCTestCase {
    func testFinishRemembersPicturesAndEmptyArrangements() throws {
        let t = makeHomeScratch()
        let set = t.write("a.als")
        let pipeline = ThumbnailPipeline(dataDir: t.sub("d"))

        guard case .image(let image) = pipeline.finish(SyntheticArrangement.make(), setPath: set) else { return XCTFail("image expected") }
        XCTAssertEqual(image.cgImage.width, ThumbnailPipeline.pixelWidth)
        XCTAssertEqual(image.cgImage.height, ThumbnailPipeline.pixelHeight)
        guard case .image? = pipeline.cached(set) else { return XCTFail("cached") }

        let other = t.write("b.als", "y")
        guard case .empty = pipeline.finish(Arrangement(), setPath: other) else { return XCTFail("empty expected") }
        guard case .empty? = pipeline.cached(other) else { return XCTFail("empty is remembered") }
    }

    func testReadErrorsAreNotRemembered() {
        let t = makeHomeScratch()
        let set = t.write("a.als")
        let pipeline = ThumbnailPipeline(dataDir: t.sub("d"))
        var broken = Arrangement()
        broken.error = "disk switched off"
        guard case .failed = pipeline.finish(broken, setPath: set) else { return XCTFail("failed expected") }
        XCTAssertNil(pipeline.cached(set))
    }

    func testProduceParsesARealSetThenServesItFromCache() async throws {
        let t = makeHomeScratch()
        let set = try t.writeSet("Song.als")
        let pipeline = ThumbnailPipeline(dataDir: t.sub("d"))
        guard case .image = await pipeline.produce(set) else { return XCTFail("image expected") }
        XCTAssertTrue(pipeline.cache.has(set))
        guard case .image? = pipeline.cachedInMemory(set) else { return XCTFail("memory hit expected") }
    }

    func testSetWithoutClipsProducesTheEmptyMark() async throws {
        let t = makeHomeScratch()
        let set = try t.writeSet("Empty.als", withClip: false)
        let pipeline = ThumbnailPipeline(dataDir: t.sub("d"))
        guard case .empty = await pipeline.produce(set) else { return XCTFail("empty expected") }
        guard case .empty? = pipeline.cached(set) else { return XCTFail("remembered") }
    }

    func testGateLimitsConcurrencyAndDropsCancelledWaiters() async {
        let gate = TaskGate(limit: 1)
        let first = await gate.acquire()
        XCTAssertTrue(first)
        let waiter = Task { await gate.acquire() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()
        let got = await waiter.value
        XCTAssertFalse(got, "a cancelled waiter leaves without running")
        gate.release()
        let again = await gate.acquire()
        XCTAssertTrue(again, "the slot is free again")
        gate.release()
    }
}
