// Mac-only: replaces upstream's registry lookup for the .als handler and Process.Start(set).
// Several Live versions may be installed; the newest one wins.
import Foundation
import AppKit

struct LiveApp: Equatable {
    let url: URL
    let version: LiveVersion
}

/// "12.0.5", "12.0b20", "11.3.20b1": release > beta of the same number.
struct LiveVersion: Comparable, Equatable {
    let numbers: [Int]
    let beta: Int?   // nil = release

    init(_ string: String) {
        let lower = string.lowercased()
        let parts = lower.split(separator: "b", maxSplits: 1, omittingEmptySubsequences: false)
        let numberPart = parts.first.map(String.init) ?? ""
        numbers = numberPart.split(separator: ".").compactMap { Int($0.filter(\.isNumber)) }
        if parts.count > 1 {
            beta = Int(parts[1].filter(\.isNumber)) ?? 0
        } else {
            beta = nil
        }
    }

    static func < (a: LiveVersion, b: LiveVersion) -> Bool {
        let count = max(a.numbers.count, b.numbers.count)
        for i in 0..<count {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        switch (a.beta, b.beta) {
        case (nil, nil): return false
        case (nil, _): return false   // a is a release, b a beta of the same number
        case (_, nil): return true
        case let (x?, y?): return x < y
        }
    }
}

enum LiveLauncherError: Error {
    case notInstalled
    case failed(String)
}

@MainActor
enum LiveLauncher {
    static let bundleIdentifier = "com.ableton.live"

    /// Every installed Live, newest first.
    static func installedApps() -> [LiveApp] {
        var urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
        urls.append(contentsOf: scanApplicationsFolder())
        var seen = Set<String>()
        let apps: [LiveApp] = urls.compactMap { url in
            let resolved = url.resolvingSymlinksInPath()
            guard seen.insert(resolved.path).inserted else { return nil }
            return LiveApp(url: resolved, version: version(ofApp: resolved))
        }
        return apps.sorted { $0.version > $1.version }
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

    private static func scanApplicationsFolder() -> [URL] {
        let folder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix("Ableton Live") && $0.hasSuffix(".app") }
            .map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    private static func version(ofApp url: URL) -> LiveVersion {
        let info = Bundle(url: url)?.infoDictionary
        let text = info?["CFBundleShortVersionString"] as? String
            ?? info?["CFBundleVersion"] as? String ?? "0"
        return LiveVersion(text)
    }
}
