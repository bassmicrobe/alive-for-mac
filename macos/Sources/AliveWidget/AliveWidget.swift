// Mac-only: the desktop widget. It draws widget.json, which the app writes into its data folder
// (WidgetSnapshot, in its `widget/` subfolder); the widget has no other data and no network. The
// sandbox lets it read only ~/Library/Application Support/Alive for Mac/widget/ (temporary-exception entitlement), so an app run
// with a custom ALIVE_HOME is invisible to it and the widget shows its placeholder.
import AliveCore
import Darwin
import SwiftUI
import WidgetKit

struct AliveEntry: TimelineEntry {
    let date: Date
    /// nil: the app has not written a snapshot yet (never opened, or a custom ALIVE_HOME).
    let snapshot: WidgetSnapshot?
}

struct AliveProvider: TimelineProvider {
    func placeholder(in context: Context) -> AliveEntry {
        AliveEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AliveEntry) -> Void) {
        completion(AliveEntry(date: Date(), snapshot: context.isPreview ? Self.sample(now: Date()) : Self.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AliveEntry>) -> Void) {
        let now = Date()
        // The app reloads timelines whenever it writes a new snapshot; this wake-up only keeps the
        // "today" figures honest across midnight.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [AliveEntry(date: now, snapshot: Self.load())],
                            policy: .after(min(midnight, now.addingTimeInterval(6 * 3600)))))
    }

    /// The real home directory: inside the sandbox `NSHomeDirectory()` is the widget's container.
    static func load() -> WidgetSnapshot? {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return nil }
        return WidgetSnapshot.load(from: WidgetSnapshot.widgetFileURL(realHome: String(cString: dir)))
    }

    /// What the widget gallery shows.
    static func sample(now: Date) -> WidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = (0..<84).compactMap { offset -> WidgetSnapshot.Day? in
            let saves = (offset * 7 + 3) % 5
            guard saves > 0, let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return WidgetSnapshot.Day(date: date, saves: saves)
        }
        let recent = ["Night Drive", "Sketch 14", "Kick study", "Pad loop", "Demo"].enumerated().map {
            WidgetSnapshot.Recent(name: $0.element, project: $0.element, modified: now.addingTimeInterval(-Double($0.offset) * 86_400))
        }
        return WidgetSnapshot(generatedAt: now, currentStreak: 6, longestStreak: 21, activeDays: 120,
                              lastActiveDay: today, days: days, recent: recent)
    }
}

struct AliveWidget: Widget {
    static let kind = "AliveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AliveProvider()) { entry in
            AliveWidgetView(entry: entry)
                .widgetURL(URL(string: "alive://home"))
                .containerBackground(for: .widget) { WidgetPalette.bg }
        }
        .configurationDisplayName("Alive")
        .description(WidgetStrings.description.s)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AliveWidgetBundle: WidgetBundle {
    var body: some Widget { AliveWidget() }
}
