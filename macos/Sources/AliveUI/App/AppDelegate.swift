// Mac-only: Finder "Open With" for .als files, activation policy for `swift run`, dark appearance.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The model the delegate forwards to; set by the main window once it exists.
    @MainActor private static weak var model: AppModel?
    /// Files that arrived before the model was attached.
    @MainActor private static var earlyPaths: [String] = []

    @MainActor static func attach(_ app: AppModel) {
        model = app
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let paths = urls.filter { $0.pathExtension.lowercased() == "als" }.map(\.path)
        guard !paths.isEmpty else { return }
        MainActor.assumeIsolated {
            if let model = AppDelegate.model {
                model.openPaths(paths)
            } else {
                AppDelegate.earlyPaths.append(contentsOf: paths)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
