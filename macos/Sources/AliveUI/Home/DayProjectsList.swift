// Port of the day menu of the year of work in src/HomeView.cs (a6c8dc1 `ShowDay`): the projects
// saved on the clicked day, busiest first. A pick takes the person to the project's tile; a project
// that has left the catalog stays listed, greyed. Shown as a popover on the calendar.
import SwiftUI

struct DayProjectsList: View {
    let pick: HeatmapDayPick
    let onPick: (String) -> Void

    private static let width: CGFloat = 280
    private static let maxListHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OverviewFormat.hover(day: pick.cell.day, saves: pick.cell.saves))
                .font(Theme.fCaption)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 8)
            if pick.projects.isEmpty {
                // A day from before the history kept its projects.
                Text(HomeStrings.dayNotRecorded.s)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(pick.projects) { project in
                            DayProjectRow(project: project, onPick: onPick)
                        }
                    }
                }
                .frame(maxHeight: Self.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(width: Self.width, alignment: .leading)
    }
}

private struct DayProjectRow: View {
    let project: DayProject
    let onPick: (String) -> Void

    var body: some View {
        if let path = project.setPath {
            Button { onPick(path) } label: { label }
                .buttonStyle(.plain)
                .rowHover(cornerRadius: 8)
        } else {
            label
                .opacity(0.45)
                .help(HomeStrings.dayProjectGone.s)
        }
    }

    private var label: some View {
        Text(project.name)
            .font(Theme.fBody)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct DayPointer: ViewModifier {
    let isLink: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isLink ? .link : nil)
        } else {
            content
        }
    }
}

extension View {
    /// The hand over a day that a click opens (a6c8dc1: such a day takes the hand as a tile does).
    func dayPointer(_ isLink: Bool) -> some View { modifier(DayPointer(isLink: isLink)) }
}
