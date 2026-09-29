// Mac-only: environment hooks so automated runs can open a given tab, set, sheet or window
// without anyone clicking. Used together with ALIVE_NO_ACTIVATE=1 and `screencapture -l`.
//
//   ALIVE_DEBUG_TAB     home | sets | plugins | samples
//   ALIVE_DEBUG_SELECT  first | last | <path of an .als in the catalog>
//   ALIVE_DEBUG_SHEET   help | filters | pluginFilters | roots-projects | roots-samples |
//                       tags | preview | rescue | export   (the last four act on the selected set)
//   ALIVE_DEBUG_PLUGIN  <plugin name>  (selects it on the Plugins tab, once the catalog is ready)
//   ALIVE_DEBUG_WINDOW  stat | player | settings   (ALIVE_DEBUG_SETTINGS_TAB=about: the About pane)
import AliveCore
import Foundation

@MainActor
enum DebugLaunch {
    private static let catalogWaitSeconds = 120

    static func apply(to app: AppModel, env: [String: String] = ProcessInfo.processInfo.environment,
                      openWindow: (String) -> Void, openSettings: () -> Void = {}) async {
        if let tab = env["ALIVE_DEBUG_TAB"].flatMap(MainTab.init(rawValue:)) { app.tab = tab }
        if let window = env["ALIVE_DEBUG_WINDOW"] {
            if window == "settings" { openSettings() }
            else if ["stat", "player"].contains(window) { openWindow(window) }
        }
        let wantsSelection = env["ALIVE_DEBUG_SELECT"] != nil
        let pluginName = env["ALIVE_DEBUG_PLUGIN"]
        let sheetName = env["ALIVE_DEBUG_SHEET"]
        guard wantsSelection || sheetName != nil || pluginName != nil else { return }
        await waitForCatalog(app)
        if let pluginName { app.plugins.show(pluginNamed: pluginName) }
        if let target = env["ALIVE_DEBUG_SELECT"] { select(target, in: app) }
        if let name = sheetName, let sheet = sheet(named: name, selected: app.selectedSetPath) {
            app.sheet = sheet
        }
        Diag.info("debug-launch: tab=\(app.tab.rawValue) selected=\(app.selectedSetPath ?? "-") sheet=\(sheetName ?? "-")")
    }

    private static func waitForCatalog(_ app: AppModel) async {
        for _ in 0..<(catalogWaitSeconds * 4) where !app.catalog.isReady {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Goes through `SetsModel.select(path:)`, the same path "Show in list" and Finder-open use,
    /// so a screenshot also proves the table scrolls to the row.
    private static func select(_ target: String, in app: AppModel) {
        let path: String?
        switch target {
        case "first": path = app.catalog.projects.first?.path
        case "last": path = app.catalog.projects.last?.path
        default: path = app.catalog.sets.contains(where: { $0.path == target }) ? target : nil
        }
        guard let path else { return }
        if app.tab == .sets { app.sets.select(path: path) } else { app.selectedSetPath = path }
    }

    static func sheet(named name: String, selected: String?) -> AppSheet? {
        switch name {
        case "help": return .help
        case "filters": return .filters
        case "pluginFilters": return .pluginFilters
        case "roots-projects": return .roots(.projects)
        case "roots-samples": return .roots(.samples)
        case "tags": return selected.map { .tags(path: $0) }
        case "preview": return selected.map { .preview(path: $0) }
        case "rescue": return selected.map { .rescue(path: $0) }
        case "export": return selected.map { .export(path: $0) }
        default: return nil
        }
    }
}
