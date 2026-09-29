// Port of src/Activity.cs
import Foundation

/// The history of the work: on which days and at which hours projects were saved.
///
/// The source is the Backup folders. Live puts a copy there on every save and writes the moment
/// of saving into its name; nothing else about the past is kept on disk. But Live keeps only the
/// TEN most recent copies per set name, so the history erases itself — precisely for the projects
/// worked on most intensively. That is why our own cache is not overwritten by a scan but
/// accumulates: a day that once made it into the history never leaves it again.
///
/// Files from the Alive subfolder inside Backup do not go into the history (they are taken over
/// the same Live save and would double the day); they are cut off by the folder name and by the
/// shape of the file name.
///
/// The object is immutable: a scan builds a new one and swaps the reference whole.
public struct Activity: Sendable {
    public static let empty = Activity(stamps: [], today: Date())

    /// Local wall-clock instants of saves, ascending.
    let stamps: [Date]
    private let byDay: [Date: Int]
    public let hourHistogram: [Int]

    public var total: Int { stamps.count }
    public var activeDays: Int { byDay.count }

    public private(set) var first: Date?
    public private(set) var last: Date?
    public private(set) var currentStreak = 0
    public private(set) var longestStreak = 0
    public private(set) var busiestDay: Date?
    public private(set) var busiestSaves = 0
    public private(set) var peakHour = -1

    /// How many saves fell on this day.
    public func saves(on day: Date) -> Int { byDay[Calendar.current.startOfDay(for: day)] ?? 0 }

    /// Every active day (start of day) with its number of saves.
    public var days: [Date: Int] { byDay }

    // MARK: building

    init(stamps unsorted: [Date], today: Date) {
        let cal = Calendar.current
        let stamps = unsorted.sorted()
        self.stamps = stamps
        var byDay: [Date: Int] = [:]
        var hours = [Int](repeating: 0, count: 24)
        for t in stamps {
            byDay[cal.startOfDay(for: t), default: 0] += 1
            hours[cal.component(.hour, from: t)] += 1
        }
        self.byDay = byDay
        self.hourHistogram = hours
        guard let firstStamp = stamps.first, let lastStamp = stamps.last else { return }
        first = firstStamp
        last = lastStamp

        for (day, n) in byDay where n > busiestSaves || (n == busiestSaves && day < (busiestDay ?? day)) {
            busiestSaves = n; busiestDay = day
        }
        for h in 0..<24 where peakHour < 0 || hours[h] > hours[peakHour] { peakHour = h }
        computeStreaks(cal, today: today)
    }

    private mutating func computeStreaks(_ cal: Calendar, today: Date) {
        let sorted = byDay.keys.sorted()
        var run = 0
        for (i, day) in sorted.enumerated() {
            if i > 0, cal.date(byAdding: .day, value: 1, to: sorted[i - 1]) == day { run += 1 } else { run = 1 }
            longestStreak = max(longestStreak, run)
        }
        // The current streak is counted from today, but the day is not over yet: if today has
        // not been sat down to, it is too early to break the streak, so we look from yesterday.
        var cursor = cal.startOfDay(for: today)
        if byDay[cursor] == nil, let y = cal.date(byAdding: .day, value: -1, to: cursor) { cursor = y }
        while byDay[cursor] != nil {
            currentStreak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
    }

    /// Builds the history out of what the scan brought in, adding it to what is already known
    /// (`previous`, usually from the cache).
    ///
    /// The .als time itself counts ONLY if the set has no copies at all. A fresh copy IS the last
    /// save: Live throws the oldest out of Backup rather than the newest, so the top mark always
    /// coincides with the current file. With live copies the .als time is either a duplicate or
    /// the trace of an edit made AROUND Live (Collect All and the rescue helper rewrite the .als
    /// themselves, and that is not a save). Taking copies alone will not do either: sets saved
    /// only once have no copies at all.
    static func build(dirs: [String], weights: [FolderScan.Weight], sets: [SetEntry],
                      previous: Activity?, now: Date = Date()) -> Activity {
        // A second is key enough: saving twice within one second is only possible from two
        // copies of Live at once. Without a key the cache would double on every scan; the
        // filtering is needed within a single walk too (a set outside a "* Project" folder makes
        // its own folder the project, which can be the parent of others' projects).
        var seen = Set<Int64>()
        var stamps: [Date] = []
        func add(_ t: Date) {
            if sane(t, now: now), seen.insert(DotNetTicks.local(t)).inserted { stamps.append(t) }
        }
        previous?.stamps.forEach(add)

        // The key is the folder plus the set name: one project folder holds different versions,
        // each with copies of its own.
        var withCopies = Set<String>()
        for (i, dir) in dirs.enumerated() where i < weights.count {
            for sv in weights[i].saves ?? [] {
                add(sv.when)
                withCopies.insert(dir.lowercased() + "|" + sv.set.lowercased())
            }
        }
        for s in sets where !s.isBackup {
            if withCopies.contains(s.projectDir.lowercased() + "|" + s.name.lowercased()) { continue }
            add(s.modified)
        }
        return Activity(stamps: stamps, today: now)
    }

    /// Does the mark look plausible? The cache accumulates and is never cleaned, so a single
    /// entry with a wrong clock would stay forever and stretch the calendar over empty decades.
    static func sane(_ t: Date, now: Date) -> Bool {
        let cal = Calendar.current
        guard cal.component(.year, from: t) >= 2000,
              let limit = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) else { return false }
        return t <= limit
    }

    // MARK: cache

    static let cacheVersion: Int32 = 1
    public static func cachePath(dir: String = AppHome.path) -> String { AppHome.file("activity.cache", in: dir) }

    /// Read up to the last intact record: a truncated tail is a lost tail, not a reason to throw
    /// away years (returning empty would overwrite the remainder with a blank at the next scan).
    public static func loadCache(dir: String = AppHome.path, now: Date = Date()) -> Activity {
        guard let data = FileManager.default.contents(atPath: cachePath(dir: dir)) else { return .empty }
        var r = DotNetReader(data)
        var stamps: [Date] = []
        do {
            guard try r.int32() == cacheVersion else { return .empty }
            let n = Int(try r.int32())
            guard n >= 0, n <= 5_000_000 else { return .empty }
            for _ in 0..<n { stamps.append(DotNetTicks.date(local: try r.int64())) }
        } catch {
            if stamps.isEmpty { Diag.warn("activity.cache unreadable: \(error)") }
        }
        return stamps.isEmpty ? .empty : Activity(stamps: stamps, today: now)
    }

    /// Not an accelerator but the only durable copy of the history, hence the atomic write.
    public func saveCache(dir: String = AppHome.path) {
        var w = DotNetWriter()
        w.int32(Activity.cacheVersion)
        w.int32(Int32(stamps.count))
        stamps.forEach { w.int64(DotNetTicks.local($0)) }
        do { try AppHome.writeAtomically(w.data, to: Activity.cachePath(dir: dir)) } catch {
            Diag.fail("activity.cache write", error)
        }
    }
}
