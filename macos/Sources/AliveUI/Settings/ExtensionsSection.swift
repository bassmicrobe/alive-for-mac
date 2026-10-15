// Mac-only: Settings section for the Quick Look preview and the desktop widget. Both are app
// extensions that macOS registers but leaves switched off; this section shows their state
// (`pluginkit -m`) and switches them on (`pluginkit -e use`). SettingsView embeds it.
import SwiftUI
import AppKit
import AliveCore

/// The two extensions packaged inside the app.
enum AppExtension: CaseIterable, Identifiable {
    case quickLook, widget

    static let appBundleID = "io.github.bassmicrobe.alive-for-mac"

    var id: String { bundleID }
    var bundleID: String {
        switch self {
        case .quickLook: return Self.appBundleID + ".quicklook"
        case .widget: return Self.appBundleID + ".widget"
        }
    }
}

enum ExtensionState: Equatable {
    case checking, enabling, enabled, disabled, notInstalled, checkFailed

    /// `pluginkit -m -i <id>` prints one line per registered copy, led by a mark column: `+` (enabled),
    /// `-` (switched off), a blank (registered but never elected, which is how a fresh install
    /// starts) or `!` / `?` / `=` (superseded or undecided); nothing at all when unknown. Only `+`
    /// counts as enabled.
    static func parse(pluginkitOutput: String) -> ExtensionState {
        let lines = pluginkitOutput.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("(") }
        guard !lines.isEmpty else { return .notInstalled }
        // Several app copies can be registered. The first can be superseded or disabled even
        // while another is elected; ordering must not turn an enabled extension into "off".
        return lines.contains { $0.hasPrefix("+") } ? .enabled : .disabled
    }
}

/// `/usr/bin/pluginkit`, run directly (no shell).
enum PluginKit {
    struct Result { let status: Int32; let output: String }

    static func run(_ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func state(of ext: AppExtension) -> ExtensionState {
        let result = run(["-m", "-i", ext.bundleID])
        if result.status != 0 { Diag.warn("pluginkit status failed (\(result.status)): \(result.output)") }
        return state(from: result)
    }

    static func state(from result: Result) -> ExtensionState {
        guard result.status == 0 else { return .checkFailed }
        return ExtensionState.parse(pluginkitOutput: result.output)
    }

    /// `pluginkit -e use -i <id>`; the failure text on error.
    static func enable(_ ext: AppExtension) -> String? {
        let result = run(["-e", "use", "-i", ext.bundleID])
        return result.status == 0 ? nil : result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ExtensionsSection: View {
    @State private var states: [AppExtension: ExtensionState] = [:]
    @State private var failure: String?
    @State private var isBusy = false

    var body: some View {
        Section(ExtensionStrings.title.s) {
            ForEach(AppExtension.allCases) { ext in row(ext) }
            if let failure {
                Text(ExtensionStrings.enableFailed.f(failure.isEmpty ? ExtensionStrings.noFailureDetails.s : failure))
                    .font(Theme.fSmall).foregroundStyle(Theme.errorText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if states.values.contains(.notInstalled) {
                Text(ExtensionStrings.notInstalledHint.s).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            }
            PillButton(title: ExtensionStrings.recheck.s) { Task { await refresh() } }
                .disabled(isBusy)
                .accessibilityLabel(ExtensionStrings.recheckAccessibility.s)
        }
        .task { await refresh() }
    }

    private func row(_ ext: AppExtension) -> some View {
        let state = states[ext] ?? .checking
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(ext)).font(Theme.fBody).foregroundStyle(Theme.text)
                    Text(statusText(state)).font(Theme.fSmall)
                        .foregroundStyle(state == .enabled ? Theme.green : Theme.secondaryText)
                }
                Spacer(minLength: 8)
                if state == .disabled {
                    PillButton(title: ExtensionStrings.enable.s, kind: .quiet) { enable(ext) }
                        .disabled(isBusy)
                        .accessibilityLabel(ExtensionStrings.enableExtension.f(title(ext)))
                }
            }
            Text(howTo(ext)).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(_ ext: AppExtension) -> String {
        ext == .quickLook ? ExtensionStrings.quickLook.s : ExtensionStrings.widget.s
    }

    private func howTo(_ ext: AppExtension) -> String {
        ext == .quickLook ? ExtensionStrings.quickLookHowTo.s : ExtensionStrings.widgetHowTo.s
    }

    private func statusText(_ state: ExtensionState) -> String {
        switch state {
        case .checking: return ExtensionStrings.stateChecking.s
        case .enabling: return ExtensionStrings.stateEnabling.s
        case .enabled: return ExtensionStrings.stateEnabled.s
        case .disabled: return ExtensionStrings.stateDisabled.s
        case .notInstalled: return ExtensionStrings.stateNotInstalled.s
        case .checkFailed: return ExtensionStrings.stateCheckFailed.s
        }
    }

    private func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        failure = nil
        states = Dictionary(uniqueKeysWithValues: AppExtension.allCases.map { ($0, .checking) })
        states = await queriedStates()
    }

    private func queriedStates() async -> [AppExtension: ExtensionState] {
        let found = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: AppExtension.allCases.map { ($0, PluginKit.state(of: $0)) })
        }.value
        return found
    }

    private func enable(_ ext: AppExtension) {
        guard !isBusy, states[ext] == .disabled else { return }
        isBusy = true
        failure = nil
        states[ext] = .enabling
        Task {
            failure = await Task.detached(priority: .userInitiated) { PluginKit.enable(ext) }.value
            states = await queriedStates()
            isBusy = false
        }
    }
}
