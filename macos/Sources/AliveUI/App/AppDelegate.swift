// Mac-only: Finder "Open With" for .als files, activation policy for `swift run`, dark appearance.
import AppKit
import AliveCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The model the delegate forwards to; set by the main window once it exists.
    @MainActor private static weak var model: AppModel?
    /// Files that arrived before the model was attached.
    @MainActor private static var earlyPaths: [String] = []

    /// A Spotlight result opened before the model was attached.
    @MainActor private static var earlySpotlightPath: String?

    @MainActor static func attach(_ app: AppModel) {
        model = app
        if let path = earlySpotlightPath {
            earlySpotlightPath = nil
            app.integration.showInAlive(path: path)
        }
        URLCommands.attach(app)
        guard !earlyPaths.isEmpty else { return }
        app.openPaths(earlyPaths)
        earlyPaths = []
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when started from `swift run` (no bundle): otherwise no menu bar, no focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ALIVE_NO_ACTIVATE=1 keeps the app in the background: automated test runs must not
        // steal keyboard focus from whoever is using the machine.
        guard ProcessInfo.processInfo.environment["ALIVE_NO_ACTIVATE"] != "1" else {
            logWindowNumbers()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// For background test runs: `screencapture -l <number>` photographs just our window
    /// (never the user's desktop). The windows appear a moment after launch.
    private func logWindowNumbers() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for window in NSApp.windows where window.isVisible {
                Diag.info("window-number: \(window.windowNumber) \(window.identifier?.rawValue ?? window.title)")
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let parts = OpenedURLs.partition(urls)
        MainActor.assumeIsolated { URLCommands.handle(parts.commands, model: AppDelegate.model) }
        let paths = parts.alsPaths
        guard !paths.isEmpty else { return }
        MainActor.assumeIsolated {
            if let model = AppDelegate.model {
                model.openPaths(paths)
            } else {
                AppDelegate.earlyPaths.append(contentsOf: paths)
            }
        }
    }

    /// A Spotlight result (`CSSearchableItemActionType`): show that set on the Sets tab.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let path = SpotlightLink.path(activityType: userActivity.activityType,
                                            userInfo: userActivity.userInfo) else { return false }
        MainActor.assumeIsolated {
            if let model = AppDelegate.model {
                model.integration.showInAlive(path: path)
            } else {
                AppDelegate.earlySpotlightPath = path
            }
        }
        return true
    }

    /// With the menu bar extra on, the app lives on after the last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !(AppDelegate.model?.settings.menuBar ?? false) }
    }
}

/// Splits what the system hands to `application(_:open:)`: `alive://` commands are never files,
/// and only real file URLs ending in `.als` may reach `openPaths` (so `alive://open/x/y.als` cannot
/// smuggle a path in).
enum OpenedURLs {
    static func partition(_ urls: [URL]) -> (commands: [URL], alsPaths: [String]) {
        let commands = urls.filter { $0.scheme?.lowercased() == URLCommand.scheme }
        let paths = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "als" }.map(\.path)
        return (commands, paths)
    }
}
