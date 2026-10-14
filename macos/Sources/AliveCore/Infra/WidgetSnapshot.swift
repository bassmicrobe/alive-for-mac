// Mac-only: the small file the app hands to the desktop widget. The widget runs in its own
// sandboxed process and cannot see the catalog, so the app writes this snapshot (widget.json in
// its data folder) whenever the catalog publishes, and the widget only reads and draws it.
import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bump when the shape changes incompatibly; a reader that does not know the version shows its placeholder.
    public static let currentVersion = 1
    public static let fileName = "widget.json"
    /// How many weeks of activity the medium and large widgets draw.
    public static let heatmapWeeks = 12
    public static let recentCount = 5
    /// Days kept in the file: the heatmap plus a margin for a widget that is not refreshed for a while.
    static let keptDays = heatmapWeeks * 7 + 14

    public struct Day: Codable, Equatable, Sendable {
        /// Start of the local day.
        public var date: Date
        public var saves: Int
        public init(date: Date, saves: Int) { self.date = date; self.saves = saves }
    }

    public struct Recent: Codable, Equatable, Sendable {
        public var name: String
        public var project: String
        public var modified: Date
        public init(name: String, project: String, modified: Date) {
            self.name = name; self.project = project; self.modified = modified
        }
    }

    public var version: Int
    public var generatedAt: Date
    public var currentStreak: Int
    public var longestStreak: Int
    /// Active days over the whole history.
    public var activeDays: Int
    /// Start of the day of the latest save: lets a stale snapshot know its streak has lapsed.
    public var lastActiveDay: Date?
    public var days: [Day]
    public var recent: [Recent]

    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, currentStreak: Int, longestStreak: Int,
                activeDays: Int, lastActiveDay: Date?, days: [Day], recent: [Recent]) {
        self.version = version; self.generatedAt = generatedAt; self.currentStreak = currentStreak
        self.longestStreak = longestStreak; self.activeDays = activeDays; self.lastActiveDay = lastActiveDay
        self.days = days; self.recent = recent
    }

    // MARK: building

    public static func make(activity: Activity, sets: [SetEntry], now: Date = Date(),
                            calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -keptDays, to: today) ?? today
        let days = activity.days
            .filter { $0.key >= from && $0.value > 0 }
            .map { Day(date: $0.key, saves: $0.value) }
            .sorted { $0.date < $1.date }
        var seenProjects = Set<String>()
        let recent = sets.filter { !$0.isBackup }
            .sorted { $0.modified > $1.modified }
            .filter { seenProjects.insert($0.projectDir).inserted }
            .prefix(recentCount)
            // Whole seconds: the file stores ISO 8601, so a fraction would never compare equal after a round trip.
            .map { Recent(name: $0.name, project: $0.projectName,
                          modified: Date(timeIntervalSince1970: $0.modified.timeIntervalSince1970.rounded(.down))) }
        return WidgetSnapshot(generatedAt: now, currentStreak: activity.currentStreak, longestStreak: activity.longestStreak,
                              activeDays: activity.activeDays,
                              lastActiveDay: activity.last.map { calendar.startOfDay(for: $0) },
                              days: days, recent: Array(recent))
    }

    // MARK: coding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// nil for damaged data or a version this reader does not know.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    /// The same picture of the work, ignoring when it was taken: the writer skips the write (and the
    /// widget reload) when nothing but the clock changed.
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        return copy == self
    }

    /// Where the sandboxed widget looks: the app's default data folder in the real home directory
    /// (`NSHomeDirectory()` would be the widget's container). A custom `ALIVE_HOME` is not visible
    /// to it: the widget then shows its placeholder.
    public static func widgetFileURL(realHome: String) -> URL {
        URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Application Support/\(AppHome.defaultFolderName)/\(fileName)")
    }

    public static func load(from url: URL) -> WidgetSnapshot? {
        (try? Data(contentsOf: url)).flatMap(decode)
    }

    // MARK: what the widget shows

    /// Saves made today according to the snapshot.
    public func savesToday(now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        return days.first { $0.date == today }?.saves ?? 0
    }

    /// The streak as of `now`: still alive when the last save was today or yesterday, lapsed otherwise
    /// (the snapshot may be a day or more old).
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastActiveDay else { return 0 }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return last >= yesterday ? currentStreak : 0
    }

    /// One heatmap cell: `saves` is nil for a day that has not happened yet.
    public struct Cell: Equatable, Sendable {
        public var date: Date
        public var saves: Int?
    }

    /// `weeks` columns of 7 days, Monday on top, the last column holding today.
    public func heatmap(now: Date, weeks: Int = WidgetSnapshot.heatmapWeeks, calendar: Calendar = .current) -> [[Cell]] {
        let today = calendar.startOfDay(for: now)
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7        // Monday = 0
        guard let lastColumn = calendar.date(byAdding: .day, value: -weekday, to: today),
              let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: lastColumn) else { return [] }
        let byDay = Dictionary(days.map { ($0.date, $0.saves) }, uniquingKeysWith: +)
        return (0..<weeks).map { col in
            (0..<7).map { row in
                let date = calendar.date(byAdding: .day, value: col * 7 + row, to: first) ?? first
                return Cell(date: date, saves: date > today ? nil : (byDay[date] ?? 0))
            }
        }
    }
}
