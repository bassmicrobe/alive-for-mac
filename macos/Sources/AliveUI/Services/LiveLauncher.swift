// Mac-only: replaces upstream's registry lookup for the .als handler and Process.Start(set).
// Several Live versions may be installed; the newest one wins.
import Foundation
import AppKit
import AliveCore

struct LiveApp: Equatable {
    let url: URL
    let version: LiveVersion
}

enum LiveLauncherError: Error {
    case notInstalled
    case failed(String)
}

@MainActor
enum LiveLauncher {
    static let bundleIdentifier = "com.ableton.live"

    /// Every installed Live, newest first: the core's scan of the Applications folders plus whatever
    /// Launch Services knows under the Live bundle identifier (a renamed or relocated copy).
    static func installedApps() -> [LiveApp] {
        let home = NSHomeDirectory()
        var apps = LiveEnvironment.findInstalls(in: ["/Applications", home + "/Applications"]).map {
            LiveApp(url: URL(fileURLWithPath: $0.appPath), version: $0.version)
        }
        for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier) {
            apps.append(LiveApp(url: url, version: version(ofApp: url)))
        }
        return newestFirst(apps)
    }

    /// Drops repeats (same resolved path) and sorts newest first.
    static func newestFirst(_ apps: [LiveApp]) -> [LiveApp] {
        var seen = Set<String>()
        let unique = apps.filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
        return unique.sorted { $0.version > $1.version }
    }

    static func newest() -> LiveApp? { installedApps().first }

    /// Opens the .als with the newest Live.
    static func open(setAt path: String) async throws {
        guard let live = newest() else { throw LiveLauncherError.notInstalled }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.open(
                [URL(fileURLWithPath: path)], withApplicationAt: live.url, configuration: config)
        } catch {
            throw LiveLauncherError.failed(error.localizedDescription)
        }
    }

    /// Launches the newest Live without a set.
    static func launch() async throws {
        guard let live = newest() else { throw LiveLauncherError.notInstalled }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: live.url, configuration: config)
        } catch {
            throw LiveLauncherError.failed(error.localizedDescription)
        }
    }

    // MARK: - Internals

    private static func version(ofApp url: URL) -> LiveVersion {
        let info = Bundle(url: url)?.infoDictionary
        let text = info?["CFBundleShortVersionString"] as? String
            ?? info?["CFBundleVersion"] as? String ?? "0"
        return LiveVersion(text) ?? LiveVersion(numbers: [0], beta: nil)
    }
}
