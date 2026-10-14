// Mac-only: the `alive://` URL scheme, for Shortcuts' "Open URLs" action and scripts.
//
//   alive://home                 show Home
//   alive://sets?q=<text>        show Sets, searching for <text>
//   alive://open?path=<set>      select the set and open it in Live (only sets of the catalog)
//   alive://latest               open the most recently modified set in Live
//   alive://random               select a random project
//   alive://rescan               rescan the folders
//   alive://samples?q=<text>     show Samples, searching for <text>
//   alive://stat                 open the Stat window
//
// Parsing and planning are pure; only `perform` touches the app. Nothing here opens an arbitrary
// file: `open` resolves its path against the catalog and opens the catalog's own entry.
import AppKit
import AliveCore
import Foundation

enum URLCommand: Equatable {
    case home
    case sets(query: String)
    case open(path: String)
    case latest
    case random
    case rescan
    case samples(query: String)
    case stat

    static let scheme = "alive"

    /// nil for another scheme, an unknown command, or a missing required argument.
    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased() else { return nil }
        func arg(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        switch host {
        case "home": return .home
        case "sets": return .sets(query: arg("q") ?? "")
        case "open":
            guard let path = arg("path"), !path.isEmpty else { return nil }
            return .open(path: path)
        case "latest": return .latest
        case "random": return .random
        case "rescan": return .rescan
        case "samples": return .samples(query: arg("q") ?? "")
        case "stat": return .stat
        default: return nil
        }
    }

    /// Whether the command needs the catalog to be loaded before it can be carried out.
    var needsCatalog: Bool {
        switch self {
        case .open, .latest, .random: return true
        case .home, .sets, .rescan, .samples, .stat: return false
        }
    }
}

/// What the app should do for a command, after looking at the catalog.
enum URLAction: Equatable {
    case showHome
    case showSets(query: String)
    case showSamples(query: String)
    /// Select the set on the Sets tab; `openInLive` as well for `open` and `latest`.
    case select(path: String, openInLive: Bool)
    case rescan
    case showStat
    /// The command was understood but cannot be carried out (unknown path, empty catalog).
    case refuse(URLRefusal)

    /// Whether carrying it out shows the main window (reopening it if it was closed).
    var presentsMainWindow: Bool {
        switch self {
        case .showHome, .showSets, .showSamples: return true
        case .select(_, let openInLive): return !openInLive
        case .rescan, .showStat, .refuse: return false
        }
    }
}

enum URLRefusal: Equatable {
    case notInCatalog(String)
    case emptyCatalog
}

enum URLCommands {
    /// Resolves `command` against the catalog's sets. `pick` chooses an index for `random`.
    static func plan(_ command: URLCommand, sets: [SetEntry], pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> URLAction {
        switch command {
        case .home: return .showHome
        case .sets(let query): return .showSets(query: query)
        case .samples(let query): return .showSamples(query: query)
        case .rescan: return .rescan
        case .stat: return .showStat
        case .open(let path):
            guard let known = resolve(path, in: sets) else { return .refuse(.notInCatalog(path)) }
            return .select(path: known.path, openInLive: true)
        case .latest:
            guard let newest = candidates(sets).max(by: { $0.modified < $1.modified }) else { return .refuse(.emptyCatalog) }
            return .select(path: newest.path, openInLive: true)
        case .random:
            let all = candidates(sets)
            guard !all.isEmpty else { return .refuse(.emptyCatalog) }
            return .select(path: all[min(max(pick(all.count), 0), all.count - 1)].path, openInLive: false)
        }
    }

    /// Real sets only: Live's Backup copies are history, not projects.
    static func candidates(_ sets: [SetEntry]) -> [SetEntry] { sets.filter { !$0.isBackup } }

    /// The catalog entry for `path`: same file after `..` and `.` are resolved, ignoring case (the
    /// usual macOS volume does). Never a path that is not in the catalog.
    static func resolve(_ path: String, in sets: [SetEntry]) -> SetEntry? {
        guard path.hasPrefix("/") else { return nil }
        let wanted = URL(fileURLWithPath: path).standardizedFileURL.path
        let all = candidates(sets)
        return all.first { $0.path == wanted } ?? all.first { $0.path.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    // MARK: carrying out

    /// How long a command waits for the catalog to finish loading.
    static let catalogWait: Duration = .seconds(60)
    /// Commands that arrived before the model existed (a cold launch by URL).
    @MainActor private static var early: [URLCommand] = []

    /// Called by `AppDelegate` for every `alive://` URL.
    @MainActor static func handle(_ urls: [URL], model: AppModel?) {
        let commands = urls.compactMap(URLCommand.parse)
        guard let model else { early.append(contentsOf: commands); return }
        commands.forEach { run($0, on: model) }
    }

    /// Called once the model is attached: runs what arrived before it.
    @MainActor static func attach(_ model: AppModel) {
        let waiting = early
        early = []
        waiting.forEach { run($0, on: model) }
    }

    @MainActor private static func run(_ command: URLCommand, on app: AppModel) {
        guard command.needsCatalog, !app.catalog.isReady else { return perform(plan(command, sets: app.catalog.sets), on: app) }
        Task { @MainActor in
            let deadline = ContinuousClock.now + catalogWait
            while !app.catalog.isReady, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(250)) }
            perform(plan(command, sets: app.catalog.sets), on: app)
        }
    }

    @MainActor static func perform(_ action: URLAction, on app: AppModel) {
        switch action {
        case .showHome:
            app.tab = .home
            bringToFront()
        case .showSets(let query):
            app.tab = .sets
            app.searchText = query
            bringToFront()
        case .showSamples(let query):
            app.tab = .samples
            app.searchText = query
            bringToFront()
        case .select(let path, let openInLive):
            app.searchText = ""
            app.tab = .sets
            app.selectedSetPath = path
            if openInLive { app.openInLive(path: path) } else { bringToFront() }
        case .rescan:
            app.catalog.rescan()
        case .showStat:
            // The Stat window is opened through SwiftUI's environment, which only a view can reach:
            // press the same menu item the person would.
            openStatWindow()
            bringToFront()
        case .refuse(let reason):
            switch reason {
            case .notInCatalog(let path): app.toast(ExtensionStrings.urlNotInCatalog.f(path), kind: .error)
            case .emptyCatalog: app.toast(ExtensionStrings.urlEmptyCatalog.s, kind: .error)
            }
        }
    }

    /// Shows the main window, reopening it when it was closed (the menu bar keeps the app alive).
    @MainActor private static func bringToFront() {
        MainWindowPresenter.show()
    }

    @MainActor private static func openStatWindow() {
        let title = CommonStrings.tabStat.s
        func find(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.title == title, item.action != nil { return item }
                if let sub = item.submenu, let found = find(in: sub) { return found }
            }
            return nil
        }
        guard let menu = NSApp.mainMenu, let item = find(in: menu) else { return }
        NSApp.sendAction(item.action!, to: item.target, from: item)
    }
}
