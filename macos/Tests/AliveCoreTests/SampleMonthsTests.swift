import XCTest
@testable import AliveCore

final class SampleMonthsTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func set(_ project: String, _ modified: Date) -> SetEntry {
        var s = SetEntry()
        s.path = "/m/\(project) Project/x.als"
        s.modified = modified
        return s
    }

    func testAProjectCountsOncePerMonthAndTheWindowIsAtLeastAYear() {
        let now = date(2026, 9, 15)
        let m = SampleMonths.count([
            set("A", date(2026, 9, 1)), set("A", date(2026, 9, 10)), set("B", date(2026, 9, 3)),
            set("A", date(2026, 7, 1)),
        ], now: now, calendar: cal)
        XCTAssertEqual(m.counts.count, 12)
        XCTAssertEqual(m.counts.last, 2)
        XCTAssertEqual(m.counts[m.counts.count - 3], 1)
        XCTAssertEqual(m.counts.reduce(0, +), 3)
        XCTAssertEqual(m.from, date(2025, 10, 1).startOfMonthUTC)
    }

    func testTheWindowReachesBackToTheFirstUseButNotBeyondFourYears() {
        let now = date(2026, 9, 15)
        let m = SampleMonths.count([set("A", date(2024, 1, 5)), set("B", date(2010, 1, 1)), set("F", date(2027, 1, 1))],
                                   now: now, calendar: cal)
        XCTAssertEqual(m.counts.count, 33)       // 2024-01 .. 2026-09; 2010 and the future are left out
        XCTAssertEqual(m.counts.first, 1)
        XCTAssertEqual(SampleMonths.count([], now: now, calendar: cal), .empty)
        XCTAssertEqual(SampleMonths.count([set("Z", .distantPast)], now: now, calendar: cal), .empty)
    }

    func testFoldersOfASetAreItsTopLevelPacks() {
        let t = makeTemp("months")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.wav(seed: 1), at: root + "/Vendor/Pack A/Kicks/k.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 2), at: root + "/Vendor/Pack A/s.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 3), at: root + "/Loose/l.wav")
        let idx = SampleIndex.build(roots: [root], disabled: [])
        var s = SetEntry()
        s.path = t.sub("m/S Project/s.als")
        s.samples = ["k.wav", "s.wav", "l.wav"].map { n in idx.path(of: idx.files.firstIndex { $0.name == n }!) }
        let u = SampleUsage.compute(index: idx, sets: [s])
        let folders = u.folders(ofSet: s.path, in: idx)
        XCTAssertEqual(folders.map { idx.folders[$0.folder].name }, ["Vendor", "Loose"])
        XCTAssertEqual(folders.map(\.count), [2, 1])
        XCTAssertEqual(u.folders(ofSet: "/none", in: idx).count, 0)
    }

    func testWavePeaksTakeTheLoudestFrameOfEveryBucket() {
        var w = WavePeaks(totalFrames: 8, buckets: 4)
        let left: [Float] = [0.1, -0.5, 0.2, 0.2, 0, 0, 0.9, -1.5]
        let right: [Float] = [0.3, 0.0, 0.0, -0.4, 0, 0, 0, 0]
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                w.add(channels: [l, r], frames: 4)
                w.add(channels: [UnsafeBufferPointer(rebasing: l[4...]), UnsafeBufferPointer(rebasing: r[4...])], frames: 4)
            }
        }
        XCTAssertEqual(w.peaks, [0.5, 0.4, 0, 1])
        XCTAssertEqual(WavePeaks(totalFrames: 0, buckets: 0).peaks.count, 1)
    }
}

private extension Date {
    var startOfMonthUTC: Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: c.dateComponents([.year, .month], from: self))!
    }
}
