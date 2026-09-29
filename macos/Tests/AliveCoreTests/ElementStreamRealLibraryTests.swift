import XCTest
@testable import AliveCore

/// Differential run + benchmark of the byte tokenizer against the original XMLParser engine on a
/// real library. Skipped unless `ALIVE_TEST_SETS=/path/to/projects` is set. Never commit paths.
final class ElementStreamRealLibraryTests: XCTestCase {
    private func sets(under root: String) -> [String] {
        var out: [String] = []
        guard let e = FileManager.default.enumerator(atPath: root) else { return out }
        while let rel = e.nextObject() as? String {
            let comps = rel.split(separator: "/")
            if comps.contains(where: { $0.caseInsensitiveCompare("Backup") == .orderedSame }) {
                e.skipDescendants()
                continue
            }
            if rel.lowercased().hasSuffix(".als"), !(comps.last ?? "").hasPrefix("._") { out.append(root + "/" + rel) }
        }
        return out.sorted()
    }

    private func root() throws -> String {
        guard let r = ProcessInfo.processInfo.environment["ALIVE_TEST_SETS"], !r.isEmpty else {
            throw XCTSkip("ALIVE_TEST_SETS not set")
        }
        return r
    }

    func testEveryRealSetParsesIdenticallyWithBothEngines() throws {
        let files = sets(under: try root())
        XCTAssertFalse(files.isEmpty)
        let lock = NSLock()
        var compared = 0, mismatches: [String] = [], unreadable = 0, withErrors = 0
        var bytes = 0
        DispatchQueue.concurrentPerform(iterations: files.count) { k in
            guard let xml = try? Gzip.readMaybeGzip(path: files[k]) else {
                lock.lock(); unreadable += 1; lock.unlock()
                return
            }
            let new = AlsFile.parse(xml: xml, path: files[k])
            let old = StreamEngines.referenceAls(xml: xml, path: files[k])
            let diff = AlsInfoComparison.differences(new, old)
            // Full event streams too (names, attributes, parents, depths): stronger than the AlsInfo view.
            let a = StreamEngines.digest(xml, useReference: false), b = StreamEngines.digest(xml, useReference: true)
            let streamSame = a.hash == b.hash && a.events == b.events && a.error == b.error
            // The other production consumer.
            let arrNew = Arrangement.parse(xml: xml), arrOld = StreamEngines.referenceArrangement(xml: xml)
            let arrSame = arrNew.tempo == arrOld.tempo && arrNew.end == arrOld.end && arrNew.creator == arrOld.creator
                && arrNew.clipCount == arrOld.clipCount && arrNew.noteCount == arrOld.noteCount
                && arrNew.tracks.map { [$0.name, String($0.clips.count), String($0.color), String($0.id)] }
                    == arrOld.tracks.map { [$0.name, String($0.clips.count), String($0.color), String($0.id)] }
                && (arrNew.error == nil) == (arrOld.error == nil)
            lock.lock()
            compared += 1
            bytes += xml.count
            if new.error != nil { withErrors += 1 }
            if !diff.isEmpty || !streamSame || !arrSame {
                mismatches.append("\(files[k]): \(diff) stream=\(streamSame) arrangement=\(arrSame)")
            }
            lock.unlock()
        }
        print("REAL DIFFERENTIAL: \(compared) sets compared (\(bytes / 1_000_000) MB inflated), \(unreadable) unreadable, "
              + "\(withErrors) with parse errors (in both engines), mismatches = \(mismatches.count)")
        for m in mismatches.prefix(10) { print("  MISMATCH \(m)") }
        XCTAssertTrue(mismatches.isEmpty)
    }

    func testBenchmarkOldVersusNew() throws {
        let all = sets(under: try root())
        let want = 60
        let stride = max(1, all.count / want)
        let sample = Swift.stride(from: 0, to: all.count, by: stride).prefix(want).map { all[$0] }

        var inflated: [Data] = []
        let g0 = Date()
        var gzBytes = 0
        for f in sample {
            gzBytes += (try? FileManager.default.attributesOfItem(atPath: f)[.size] as? Int) ?? 0
            if let d = try? Gzip.readMaybeGzip(path: f) { inflated.append(d) }
        }
        let gunzip = Date().timeIntervalSince(g0)
        let mb = Double(inflated.reduce(0) { $0 + $1.count }) / 1_000_000

        func time(_ body: (Data) -> Void) -> Double {
            let t = Date()
            for d in inflated { body(d) }
            return Date().timeIntervalSince(t)
        }
        let newT = time { _ = AlsFile.parse(xml: $0) }
        let oldT = time { _ = StreamEngines.referenceAls(xml: $0) }
        let newArr = time { _ = Arrangement.parse(xml: $0) }
        func line(_ name: String, _ t: Double) {
            print(String(format: "  %@: %.2fs  %.1f MB/s  %.2f sets/s", name, t, mb / t, Double(inflated.count) / t))
        }
        print(String(format: "BENCHMARK %d sets, %.0f MB inflated (%.0f MB gz), gunzip alone %.2fs (%.0f MB/s)",
                     inflated.count, mb, Double(gzBytes) / 1e6, gunzip, mb / gunzip))
        line("AlsInfo, XMLParser (old)", oldT)
        line("AlsInfo, tokenizer (new)", newT)
        print(String(format: "  speedup %.1fx", oldT / newT))
        line("Arrangement, tokenizer (new)", newArr)
    }
}
