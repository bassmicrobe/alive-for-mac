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

    /// One save: when, and the project folder it was made in — "" for a save the history took in
    /// before it kept folders (upstream a6c8dc1 `Mark`).
    struct Mark: Equatable, Sendable {
        var when: Date
        var project: String
    }

    /// The saves, ascending by time (local wall-clock instants).
    let marks: [Mark]
    var stamps: [Date] { marks.map(\.when) }
    private let byDay: [Date: Int]
    public let hourHistogram: [Int]

    public var total: Int { marks.count }
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

    /// The project folders saved in on that day, the busiest first — what a day's cell in the
    /// year of work opens (upstream a6c8dc1 `ProjectsOn`). The folders are the same strings as
    /// `SetEntry.projectDir`. Ties keep the order of the first save that day. Saves the history
    /// took in before it kept folders name nothing, so a day of those alone gives an empty list.
    public func projects(on day: Date) -> [String] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        var order: [String] = []                       // first spelling seen, in first-save order
        var saves: [String: Int] = [:]                 // keyed case-insensitively, like upstream
        var i = firstMark(onOrAfter: start)
        while i < marks.count, marks[i].when < end {
            let project = marks[i].project
            i += 1
            if project.isEmpty { continue }
            let key = project.lowercased()
            if saves[key] == nil { order.append(project) }
            saves[key, default: 0] += 1
        }
        // The tie-break is spelled out rather than left to the stability of the sort.
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.lowercased(), $0) })
        return order.sorted {
            let a = saves[$0.lowercased()] ?? 0, b = saves[$1.lowercased()] ?? 0
            return a != b ? a > b : (rank[$0.lowercased()] ?? 0) < (rank[$1.lowercased()] ?? 0)
        }
    }

    /// Position of the first save at or after `t` (the marks are ascending).
    private func firstMark(onOrAfter t: Date) -> Int {
        var lo = 0, hi = marks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if marks[mid].when < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Every active day (start of day) with its number of saves.
    public var days: [Date: Int] { byDay }

    // MARK: building

    /// Saves with no project folder (a history from before folders were kept, and tests).
    init(stamps: [Date], today: Date) {
        self.init(marks: stamps.map { Mark(when: $0, project: "") }, today: today)
    }

    init(marks unsorted: [Mark], today: Date) {
        let cal = Calendar.current
        let marks = unsorted.sorted { $0.when < $1.when }
        self.marks = marks
        var byDay: [Date: Int] = [:]
        var hours = [Int](repeating: 0, count: 24)
        for m in marks {
            byDay[cal.startOfDay(for: m.when), default: 0] += 1
            hours[cal.component(.hour, from: m.when)] += 1
        }
        self.byDay = byDay
        self.hourHistogram = hours
        guard let firstMark = marks.first, let lastMark = marks.last else { return }
        first = firstMark.when
        last = lastMark.when

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
        var seen: [Int64: Int] = [:]          // a moment -> its place in marks
        var marks: [Mark] = []
        // A moment already known is not counted again — but if it came without a project (a
        // history from before folders were kept) and the walk has just found it in a Backup
        // folder, it gets that folder now (upstream `Add`).
        func add(_ t: Date, _ project: String) {
            guard sane(t, now: now) else { return }
            let key = DotNetTicks.local(t)
            if let i = seen[key] {
                if marks[i].project.isEmpty { marks[i].project = project }
                return
            }
            seen[key] = marks.count
            marks.append(Mark(when: t, project: project))
        }
        previous?.marks.forEach { add($0.when, $0.project) }

        // The key is the folder plus the set name: one project folder holds different versions,
        // each with copies of its own. Each save remembers the project folder it was made in.
        var withCopies = Set<String>()
        for (i, dir) in dirs.enumerated() where i < weights.count {
            for sv in weights[i].saves ?? [] {
                add(sv.when, dir)
                withCopies.insert(dir.lowercased() + "|" + sv.set.lowercased())
            }
        }
        for s in sets where !s.isBackup {
            if withCopies.contains(s.projectDir.lowercased() + "|" + s.name.lowercased()) { continue }
            add(s.modified, s.projectDir)
        }
        return Activity(marks: marks, today: now)
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
    /// The projects follow the moments as a tail behind this mark ("proj"), one folder per moment
    /// in the same order. Not a new version: a copy of Alive from before would read a new version
    /// as nothing and, at its next scan, write the history over with only what is left in Backup.
    /// A tail it simply does not reach (upstream a6c8dc1 `ProjectsMark`).
    static let projectsMark: Int32 = 0x6A6F7270
    public static func cachePath(dir: String = AppHome.path) -> String { AppHome.file("activity.cache", in: dir) }

    /// Read up to the last intact record: a truncated tail is a lost tail, not a reason to throw
    /// away years (returning empty would overwrite the remainder with a blank at the next scan).
    public static func loadCache(dir: String = AppHome.path, now: Date = Date()) -> Activity {
        readCache(dir: dir, now: now).activity
    }

    /// `loadCache`, and whether the cache exists but could not be read (permissions, an I/O error).
    /// An absent cache is an ordinary first run and starts empty. An unread one is the only
    /// durable copy of the history, so it must not be replaced by what a scan finds in Backup:
    /// the caller leaves the file alone (`ProjectIndex` skips `saveCache`) until a read works.
    public static func readCache(dir: String = AppHome.path, now: Date = Date()) -> (activity: Activity, isUnread: Bool) {
        let path = cachePath(dir: dir)
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            if AppHome.isAbsent(error) { return (.empty, false) }
            Diag.warn("activity.cache exists but cannot be read, so it will not be replaced: \(error.localizedDescription)")
            return (.empty, true)
        }
        var r = DotNetReader(data)
        var ticks: [Int64] = []
        var complete = false
        do {
            let version = try r.int32()
            guard version == cacheVersion else {
                Diag.warn("activity.cache has version \(version), not \(cacheVersion): starting with an empty history (the file is kept as activity.cache.bak at the next save)")
                return (.empty, false)
            }
            let n = Int(try r.int32())
            guard n >= 0, n <= 5_000_000 else {
                Diag.warn("activity.cache claims \(n) moments: starting with an empty history (the file is kept as activity.cache.bak at the next save)")
                return (.empty, false)
            }
            for _ in 0..<n { ticks.append(try r.int64()) }
            complete = true
        } catch {
            Diag.warn("activity.cache is cut short after \(ticks.count) moments: \(error)")
        }
        // The projects are read by the record's place in the file, so a damaged moment (skipped
        // below) does not shift the folders of the ones after it.
        let projects = complete ? readProjects(&r, count: ticks.count) : []
        var marks: [Mark] = []
        marks.reserveCapacity(ticks.count)
        for (i, t) in ticks.enumerated() where DotNetTicks.isValid(ticks: t) {
            marks.append(Mark(when: DotNetTicks.date(local: t), project: i < projects.count ? projects[i] : ""))
        }
        return (marks.isEmpty ? .empty : Activity(marks: marks, today: now), false)
    }

    /// The tail behind `projectsMark`, if this history has one. A tail cut short gives the
    /// folders it got to; the rest are unnamed.
    private static func readProjects(_ r: inout DotNetReader, count: Int) -> [String] {
        guard r.remaining >= 4, (try? r.int32()) == projectsMark else {
            if r.remaining > 0 { Diag.warn("activity.cache: unknown data behind the moments, the project folders are not read") }
            return []
        }
        var out: [String] = []
        out.reserveCapacity(min(count, r.remaining))
        var shared: [String: String] = [:]      // one project is named by thousands of saves
        for _ in 0..<count {
            guard let name = try? r.string() else {
                Diag.warn("activity.cache: the project folders end after \(out.count) of \(count) saves")
                break
            }
            if let known = shared[name] { out.append(known) } else { shared[name] = name; out.append(name) }
        }
        return out
    }

    /// Not an accelerator but the only durable copy of the history, hence the atomic write and the
    /// previous file kept as `activity.cache.bak`. The folders are written only once at least one
    /// save has one: without them the file is the old format byte for byte.
    public func saveCache(dir: String = AppHome.path) {
        var w = DotNetWriter()
        w.int32(Activity.cacheVersion)
        w.int32(Int32(clamping: marks.count))
        marks.forEach { w.int64(DotNetTicks.local($0.when)) }
        if marks.contains(where: { !$0.project.isEmpty }) {
            w.int32(Activity.projectsMark)
            marks.forEach { w.string($0.project) }
        }
        do { try AppHome.writeKeepingBackup(w.data, to: Activity.cachePath(dir: dir)) } catch {
            Diag.fail("activity.cache write", error)
        }
    }
}
