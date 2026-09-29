// Port of src/SettingsDialog.cs, reduced to the Mac settings: language, transparency, plugin
// source, data folder. Update controls come from `UpdatesSection` (S5).
import SwiftUI
import AliveCore

struct SettingsView: View {
    private enum Pane { case general, about }

    /// ALIVE_DEBUG_SETTINGS_TAB=about opens the About pane (automated screenshots, see DebugLaunch).
    @State private var pane: Pane = ProcessInfo.processInfo.environment["ALIVE_DEBUG_SETTINGS_TAB"] == "about"
        ? .about : .general

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsView()
                .tabItem { Label(SettingsStrings.tabGeneral.s, systemImage: "gearshape") }
                .tag(Pane.general)
            AboutView()
                .tabItem { Label(SettingsStrings.tabAbout.s, systemImage: "info.circle") }
                .tag(Pane.about)
        }
        .frame(width: 540, height: 560)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker(SettingsStrings.language.s, selection: $prefs.language) {
                    ForEach(LanguagePreference.allCases) { option in
                        Text(option.nativeName ?? SettingsStrings.languageSystem.s).tag(option)
                    }
                }
                Text(SettingsStrings.languageNote.s)
                    .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(SettingsStrings.transparency.s, isOn: $prefs.transparency)
                Text(SettingsStrings.transparencyHelp.s)
                    .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            }
            Section {
                Picker(SettingsStrings.pluginSource.s, selection: $prefs.pluginSource) {
                    Text(SettingsStrings.pluginSourceLive.s).tag(PluginSource.liveDatabase)
                    Text(SettingsStrings.pluginSourceFolders.s).tag(PluginSource.pluginFolders)
                }
                Text(SettingsStrings.pluginSourceHelp.s)
                    .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            }
            Section(SettingsStrings.dataFolder.s) {
                LabeledContent {
                    PillButton(title: SettingsStrings.openDataFolder.s, action: openDataFolder)
                } label: {
                    Text(AppHome.path)
                        .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            UpdatesSection()
        }
        .formStyle(.grouped)
    }

    private func openDataFolder() {
        do {
            try Finder.openFolder(path: AppHome.ensure(app.dataDir))
        } catch {
            app.toast(CommonStrings.folderOpenFailed.f(error.localizedDescription), kind: .error)
        }
    }
}
