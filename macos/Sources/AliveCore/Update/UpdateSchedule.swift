// Port of the scheduling in src/MainForm.cs (CheckUpdatesInBackground) and the dot on the gear.
import Foundation

/// When the background check runs and whether it lights the dot. Pure, so it can be tested.
public enum UpdateSchedule {
    /// Today's date in local time as `yyyy-MM-dd`, the form `lastupdatecheck` is written in.
    public static func dayKey(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Once a day, and only when the person has switched it on. The day is written down even when
    /// the answer was no use, so a machine with no network does not retry on every scan.
    public static func isDue(enabled: Bool, lastCheck: String, today: String) -> Bool {
        enabled && lastCheck != today
    }

    /// The dot is for a release that moved the major or minor number and that the person has not
    /// looked at yet; a fix waits for somebody to ask.
    public static func shouldLightDot(_ outcome: UpdateCheck.Outcome, seen: String) -> Bool {
        guard case .newer(let release, let step) = outcome, step == .big else { return false }
        return release.version != seen
    }
}
