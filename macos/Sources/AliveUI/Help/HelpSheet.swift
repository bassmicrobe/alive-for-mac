// Port of src/HelpOverlay.cs: what the tabs show and which keys do what (Mac mapping, docs/PORTING.md §7).
import SwiftUI

private struct ShortcutRow: Identifiable {
    let keys: [String]
    let action: HelpStrings
    var id: String { keys.joined() + action.en }
}

private struct ShortcutGroup: Identifiable {
    let title: HelpStrings
    let rows: [ShortcutRow]
    var id: String { title.en }
}

private let shortcutGroups: [ShortcutGroup] = [
    ShortcutGroup(title: .groupNavigation, rows: [
        ShortcutRow(keys: ["⌘", "1"], action: .goHome),
        ShortcutRow(keys: ["⌘", "2"], action: .goSets),
        ShortcutRow(keys: ["⌘", "3"], action: .goPlugins),
        ShortcutRow(keys: ["⌘", "4"], action: .goSamples),
        ShortcutRow(keys: ["⌘", "5"], action: .openStat),
        ShortcutRow(keys: ["⌘", "F"], action: .focusSearch),
        ShortcutRow(keys: ["⌥", "⌘", "F"], action: .openFilters),
        ShortcutRow(keys: ["⇧", "⌘", "O"], action: .scanFolders),
        ShortcutRow(keys: ["⌘", "R"], action: .rescan),
    ]),
    ShortcutGroup(title: .groupSets, rows: [
        ShortcutRow(keys: ["⌘", "O"], action: .openInLive),
        ShortcutRow(keys: ["↩"], action: .listReturn),
        ShortcutRow(keys: ["⇧", "⌘", "R"], action: .showInFinder),
        ShortcutRow(keys: ["⌘", "D"], action: .pinSet),
        ShortcutRow(keys: ["⌘", "T"], action: .tagsAndNotes),
        ShortcutRow(keys: ["⌥", "⌘", "R"], action: .rescueSet),
        ShortcutRow(keys: ["⌘", "E"], action: .exportSet),
    ]),
    ShortcutGroup(title: .groupSamples, rows: [
        ShortcutRow(keys: ["←", "→"], action: .sampleFolder),
        ShortcutRow(keys: ["Space"], action: .sampleAudition),
        ShortcutRow(keys: ["↩"], action: .sampleOpen),
        ShortcutRow(keys: ["⇧", "↩"], action: .sampleReveal),
    ]),
    ShortcutGroup(title: .groupPlayback, rows: [
        ShortcutRow(keys: ["Space"], action: .listSpace),
        ShortcutRow(keys: ["⌥", "⌘", "P"], action: .playPause),
        ShortcutRow(keys: ["⌘", "Y"], action: .arrangementPreview),
    ]),
    ShortcutGroup(title: .groupGeneral, rows: [
        ShortcutRow(keys: ["⌘", "N"], action: .launchLive),
        ShortcutRow(keys: ["⌘", ","], action: .openSettings),
        ShortcutRow(keys: ["⌘", "?"], action: .openHelp),
        ShortcutRow(keys: ["⌃", "⌘", "F"], action: .fullscreen),
        ShortcutRow(keys: ["⌘", "M"], action: .minimize),
        ShortcutRow(keys: ["⌘", "Q"], action: .quit),
    ]),
]

struct HelpSheet: View {
    private let columns = [GridItem(.flexible(), spacing: 14, alignment: .top),
                           GridItem(.flexible(), spacing: 14, alignment: .top)]

    var body: some View {
        SheetFrame(title: HelpStrings.title.s, width: 760, height: 620) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tabsCard
                    SectionHeader(HelpStrings.shortcuts.s)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shortcutGroups) { group in
                            GroupCard(group: group)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var tabsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(HelpStrings.tabsTitle.s).font(Theme.fTitle).foregroundStyle(Theme.text)
                tabLine(CommonStrings.tabHome.s, HelpStrings.aboutHome.s)
                tabLine(CommonStrings.tabSets.s, HelpStrings.aboutSets.s)
                tabLine(CommonStrings.tabPlugins.s, HelpStrings.aboutPlugins.s)
                tabLine(CommonStrings.tabSamples.s, HelpStrings.aboutSamples.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tabLine(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(Theme.fBody).foregroundStyle(Theme.text).frame(width: 80, alignment: .leading)
            Text(text).font(Theme.fBody).foregroundStyle(Theme.textDim)
        }
    }
}

private struct GroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(group.title.s).font(Theme.fTitle).foregroundStyle(Theme.text)
                ForEach(group.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.action.s).font(Theme.fBody).foregroundStyle(Theme.textDim)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        HStack(spacing: 3) {
                            ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in KeyCap(text: key) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One key of a combination: "⇧ ⌘ R" is three caps, as in upstream's overlay.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 20)
            .padding(.horizontal, 4)
            .frame(height: 20)
            .background(Theme.surfacePressed, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
