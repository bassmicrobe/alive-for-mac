// Mac-only: the widget's words, English or Japanese by the system language.
import Foundation

enum WidgetStrings: CaseIterable {
    case description, streak, streakDays, savesToday, activeDays, recentProjects, noData, noDataHint, noRecent, noStreak

    private static let isJapanese = Locale.preferredLanguages.first?.lowercased().hasPrefix("ja") == true

    static var locale: Locale { Locale(identifier: isJapanese ? "ja_JP" : "en_US") }

    var s: String { Self.isJapanese ? text.ja : text.en }

    private var text: (en: String, ja: String) {
        switch self {
        case .description: return ("Your streak, saves and recent projects.", "連続記録・保存回数・最近のプロジェクト。")
        case .streak: return ("Streak", "連続日数")
        case .streakDays: return ("day streak", "日連続")
        case .savesToday: return ("saves today", "今日の保存")
        case .activeDays: return ("active days", "作業した日")
        case .recentProjects: return ("Recent projects", "最近のプロジェクト")
        case .noData: return ("No data yet", "データがありません")
        case .noDataHint: return ("Open Alive for Mac once to fill this widget.", "Alive for Mac を一度開くと表示されます。")
        case .noRecent: return ("No projects yet", "プロジェクトなし")
        case .noStreak: return ("No streak", "連続記録なし")
        }
    }
}
