// Port of the DetailPanel that upstream's Stat window hosts on the right (src/DetailPanel.cs), reduced
// to what a dot needs: name, picture, path, tags, note, files, plugins and the three actions.
import SwiftUI
import AliveCore

struct StatInspector: View {
    @Environment(AppModel.self) private var app
    let model: StatModel
    let onShowInList: () -> Void

    var body: some View {
        SurfaceCard(padding: Theme.panelPad + 2) {
            if let set = model.selectedSet {
                details(set)
            } else {
                EmptyState(icon: .nebula, title: StatStrings.inspectorEmptyTitle.s,
                           message: StatStrings.inspectorEmptyBody.s)
            }
        }
        .frame(width: Theme.panelW)
    }

    private func details(_ set: SetEntry) -> some View {
        let meta = app.sets.meta
        let tags = meta.tagsOf(set.projectDir)
        let note = meta.noteOf(set.projectDir)
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(set.name)
                            .font(Theme.fHead)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(Metrics.bytes(set.projectSize))
                            .font(Theme.fBody)
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                    }
                    ArrangementThumbnailView(path: set.path)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.thumbR, style: .continuous))
                    Text(set.path)
                        .font(Theme.fSmall)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(4)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if !tags.isEmpty {
                        TagFlow(spacing: 6) { ForEach(tags, id: \.self) { TagPill(text: $0) } }
                    }
                    if !note.isEmpty { field(StatStrings.note.s, note) }
                    if set.projectFiles > 0 { field(StatStrings.files.s, "\(set.projectFiles)") }
                    plugins(set)
                }
            }
            .scrollIndicators(.never)
            actions(set)
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            Text(value).font(Theme.fBody).foregroundStyle(Theme.text).textSelection(.enabled)
        }
    }

    private func plugins(_ set: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(StatStrings.plugins.f(set.plugins.count)).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            if set.plugins.isEmpty {
                Text(StatStrings.noPlugins.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(Array(set.plugins.enumerated()), id: \.offset) { _, name in
                    Text(name).font(Theme.fBody).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
        }
    }

    private func actions(_ set: SetEntry) -> some View {
        VStack(spacing: 8) {
            PillButton(title: CommonStrings.openInLive.s, kind: .primary) { model.openSelectedInLive() }
                .frame(maxWidth: .infinity)
            HStack(spacing: Theme.iconGap) {
                PillButton(title: StatStrings.showInList.s, icon: .viewList, action: onShowInList)
                    .frame(maxWidth: .infinity)
                CircleIconButton(icon: .folder, help: CommonStrings.showInFinder.s) { model.revealSelected() }
            }
        }
    }
}

/// Left-to-right layout that wraps to the next line: the tag pills of a project.
struct TagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, in: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(subviews, in: bounds.width)
        for (subview, origin) in zip(subviews, laid.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), origins)
    }
}
