// Mac-only: menu bar with every shortcut of the table in docs/PORTING.md §7 (Mac column).
// Standard ⌘M / ⌘Q / ⌃⌘F / ⌘, come from the system (Window menu, app menu, Settings scene).
// Space in a focused list is handled by the list views themselves (`onKeyPress`).
import SwiftUI

struct AppCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File: replaces "New" with launching Live.
        CommandGroup(replacing: .newItem) {
            Button(CommonStrings.launchLive.s) { app.launchLive() }
                .keyboardShortcut("n", modifiers: .command)
            Button(CommonStrings.openInLive.s) { app.openSelectedInLive() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!app.hasSelectedSet)
            Button(CommonStrings.scanFolders.s) { app.presentScanFolders() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu(CommonStrings.menuSet.s) {
            Button(CommonStrings.showInFinder.s) { app.revealSelectedInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!app.hasSelectedSet)
            Button(CommonStrings.pin.s) { app.togglePinSelected() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!app.hasSelectedSet)
            Button(CommonStrings.tagsAndNotes.s) { app.presentTags() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!app.hasSelectedSet)
            Divider()
            Button(CommonStrings.playPause.s) { app.playPauseContextual() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button(CommonStrings.arrangementPreview.s) { app.presentPreview() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(!app.hasSelectedSet)
            Divider()
            Button(CommonStrings.rescue.s) { app.presentRescue() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!app.hasSelectedSet)
            Button(CommonStrings.exportSet.s) { app.presentExport() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!app.hasSelectedSet)
            Divider()
            Button(CommonStrings.rescan.s) { app.rescan() }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(before: .toolbar) {
            Button(CommonStrings.tabHome.s) { app.tab = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button(CommonStrings.tabSets.s) { app.tab = .sets }
                .keyboardShortcut("2", modifiers: .command)
            Button(CommonStrings.tabPlugins.s) { app.tab = .plugins }
                .keyboardShortcut("3", modifiers: .command)
            Button(CommonStrings.tabSamples.s) { app.tab = .samples }
                .keyboardShortcut("4", modifiers: .command)
            Button(CommonStrings.tabStat.s) { openWindow(id: "stat") }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
            Button(CommonStrings.focusSearch.s) { app.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button(CommonStrings.filters.s) { app.presentFilters() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!app.canPresentFilters)
            Divider()
        }

        // ⌘? is ⇧⌘/ on the keyboard.
        CommandGroup(replacing: .help) {
            Button(CommonStrings.help.s) { app.presentHelp() }
                .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}
