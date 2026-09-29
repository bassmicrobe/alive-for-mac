import XCTest
@testable import AliveCore

/// Real-library smoke test, skipped unless `ALIVE_TEST_SETS=/path/to/projects` is set.
/// It scans the folder with a private data dir, parses every set and reports count, errors and
/// throughput. Never commit user data or paths.
final class RealLibraryTests: XCTestCase {
    func testScanAndParseEverySet() throws {
        guard let root = ProcessInfo.processInfo.environment["ALIVE_TEST_SETS"], !root.isEmpty else {
            throw XCTSkip("ALIVE_TEST_SETS not set")
        }
        let data = makeTemp("real-data")
        let idx = ProjectIndex(dir: data.path, settings: Settings())
        let lastProgress = Counter()
        let stats = idx.scan(roots: [root], progress: { done, _, _ in lastProgress.raise(to: done) })
        let sets = idx.sets
        let errors = sets.filter { !$0.error.isEmpty }
        let perSecond = stats.seconds > 0 ? Double(stats.parsed) / stats.seconds : 0
        print("REAL LIBRARY: \(sets.count) sets, \(stats.parsed) parsed, \(errors.count) with errors, "
              + String(format: "%.1fs, %.1f sets/s (walk + parse + renders + weights)", stats.seconds, perSecond))
        for e in errors.prefix(10) { print("  error: \(e.path) -> \(e.error)") }
        let withPlugins = sets.filter { !$0.plugins.isEmpty }.count
        let au = sets.flatMap(\.pluginUids).filter { $0.hasPrefix("au:") }.count
        print("  with plugins: \(withPlugins); AU refs: \(au); with tempo: \(sets.filter { $0.tempo > 0 }.count); with key: \(sets.filter { !$0.key.isEmpty }.count)")
        XCTAssertGreaterThan(sets.count, 0)
        XCTAssertGreaterThan(lastProgress.value, 0)
        XCTAssertLessThan(Double(errors.count), Double(sets.count) * 0.05, "more than 5% of sets failed to parse")

        // Second pass: everything unchanged must come from the cache.
        let again = idx.scan(roots: [root])
        print("  rescan: parsed \(again.parsed), reused \(again.reused), \(String(format: "%.1fs", again.seconds))")
        XCTAssertEqual(again.parsed, 0)

        // Pure parse throughput on the AlsFile parser alone (no walk/renders/weights).
        let sample = Array(sets.prefix(200))
        let t0 = Date()
        var parsed = 0
        for s in sample where AlsFile.read(path: s.path).error == nil { parsed += 1 }
        let dt = Date().timeIntervalSince(t0)
        print("  AlsFile.read serial: \(parsed) sets in \(String(format: "%.2fs", dt)) = \(String(format: "%.1f", Double(parsed) / max(dt, 0.001))) sets/s per thread")

        // The library's real Live environment.
        let env = LiveEnvironment.detect()
        print("  Live install: \(env.installDir.isEmpty ? "none" : env.installDir); newest prefs: \(env.newestPrefsFolder ?? "none"); user library: \(env.userLibrary)")
    }
}
