// Port of src/HelpOverlay.cs: what the tabs show and which keys do what (Mac mapping, docs/PORTING.md §7).
// The card is as tall as its content and only scrolls when the window is too low for it (a6c8dc1).
import AppKit
import SwiftUI

struct ShortcutRow: Identifiable {
    let keys: [String]
    let action: HelpStrings
    var id: String { keys.joined() + action.en }
}

struct ShortcutGroup: Identifiable {
    let title: HelpStrings
    let rows: [ShortcutRow]
    var id: String { title.en }
}

let shortcutGroups: [ShortcutGroup] = [
    ShortcutGroup(title: .groupNavigation, rows: [
        ShortcutRow(keys: ["⌘", "1"], action: .goHome),
        ShortcutRow(keys: ["⌘", "2"], action: .goSets),
        ShortcutRow(keys: ["⌘", "3"], action: .goPlugins),
        ShortcutRow(keys: ["⌘", "4"], action: .goSamples),
        ShortcutRow(keys: ["⌘", "5"], action: .openStat),
        ShortcutRow(keys: ["⌘", "F"], action: .focusSearch),
        ShortcutRow(keys: ["↓"], action: .searchIntoResults),
        ShortcutRow(keys: ["Home", "End"], action: .listEnds),
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
    ShortcutGroup(title: .groupPreview, rows: [
        ShortcutRow(keys: ["⌘", "Y"], action: .arrangementPreview),
        ShortcutRow(keys: ["Wheel"], action: .previewWheel),
        ShortcutRow(keys: ["⇧", "Wheel"], action: .previewShiftWheel),
        ShortcutRow(keys: ["⌘", "Wheel"], action: .previewCommandWheel),
        ShortcutRow(keys: ["⌥", "Wheel"], action: .previewOptionWheel),
        ShortcutRow(keys: ["Middle drag"], action: .previewMiddleDrag),
    ]),
    ShortcutGroup(title: .groupSamples, rows: [
        ShortcutRow(keys: ["Space"], action: .sampleAudition),
        ShortcutRow(keys: ["→"], action: .samplePlay),
        ShortcutRow(keys: ["←"], action: .sampleCollapse),
        ShortcutRow(keys: ["Click"], action: .sampleEmptyClick),
        ShortcutRow(keys: ["↩"], action: .sampleOpen),
        ShortcutRow(keys: ["⇧", "↩"], action: .sampleReveal),
    ]),
    ShortcutGroup(title: .groupPlayback, rows: [
        ShortcutRow(keys: ["Space"], action: .listSpace),
        ShortcutRow(keys: ["⌥", "⌘", "P"], action: .playPause),
        ShortcutRow(keys: ["⇧", "↩"], action: .playerReveal),
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

/// The groups in two columns, in order, split where about half of the rows have been placed.
enum HelpColumns {
    static func split(_ groups: [ShortcutGroup]) -> (left: [ShortcutGroup], right: [ShortcutGroup]) {
        let weights = groups.map { $0.rows.count + 2 }          // a title and the gap count too
        let half = Double(weights.reduce(0, +)) / 2
        var placed = 0
        var cut = 0
        for weight in weights {
            // The group that crosses the middle goes where it overshoots less.
            if Double(placed + weight) > half && Double(placed + weight) - half > half - Double(placed) { break }
            placed += weight
            cut += 1
            if Double(placed) >= half { break }
        }
        return (Array(groups[..<cut]), Array(groups[cut...]))
    }
}

struct HelpSheet: View {
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        SheetFrame(title: HelpStrings.title.s, width: 760) {
            ScrollView {
                content
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: HelpContentHeight.self, value: proxy.size.height)
                    })
            }
            .onPreferenceChange(HelpContentHeight.self) { contentHeight = $0 }
            // As tall as what it shows; scrolls only when the window cannot hold all of it.
            .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        }
    }

    private var content: some View {
        let columns = HelpColumns.split(shortcutGroups)
        return VStack(alignment: .leading, spacing: Theme.s(18)) {
            tabsCard
            IntegrationHelpCard()
            SectionHeader(HelpStrings.shortcuts.s)
            HStack(alignment: .top, spacing: Theme.s(14)) {
                column(columns.left)
                column(columns.right)
            }
        }
        .padding(.bottom, Theme.s(4))
    }

    private func column(_ groups: [ShortcutGroup]) -> some View {
        VStack(spacing: Theme.s(14)) {
            ForEach(groups) { GroupCard(group: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// The room a sheet has: the window it hangs from, less the sheet's own frame and a margin.
    private var maxHeight: CGFloat {
        let window = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView?.bounds.height ?? 800
        return max(Theme.s(280), window - Theme.pad * 2 - Theme.s(110))
    }

    private var tabsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.s(8)) {
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
        HStack(alignment: .firstTextBaseline, spacing: Theme.s(10)) {
            Text(name).font(Theme.fBody).foregroundStyle(Theme.text)
                .frame(width: Theme.s(80), alignment: .leading)
            Text(text).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct HelpContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct GroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.s(9)) {
                Text(group.title.s).font(Theme.fTitle).foregroundStyle(Theme.text)
                ForEach(group.rows) { row in
                    HStack(spacing: Theme.s(8)) {
                        Text(row.action.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                        Spacer(minLength: Theme.s(6))
                        HStack(spacing: Theme.s(3)) {
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
            .font(.system(size: Theme.s(11), weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(minWidth: Theme.s(20))
            .padding(.horizontal, Theme.s(4))
            .frame(height: Theme.s(20))
            .background(Theme.surfacePressed, in: RoundedRectangle(cornerRadius: Theme.s(5), style: .continuous))
    }
}
