// Port of the set sections of src/DetailPanel.cs (Header, Thumb, path, TagsAndNote, Versions, Files,
// sample folders, Plugins), as SwiftUI views.
import SwiftUI
import AliveCore

// MARK: - Building blocks

/// A dim heading with an optional value on the right ("Plugins (8):" … "2 missing").
private struct PanelHeading: View {
    let title: String
    var trailing: String?
    var trailingTint: Color = Theme.red

    var body: some View {
        HStack {
            Text(title).font(Theme.fLabel).foregroundStyle(Theme.textDim)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(Theme.fLabel).foregroundStyle(trailingTint)
            }
        }
    }
}

/// A row that leads somewhere: underlined under the cursor, like upstream's clickable rows.
private struct PanelLinkRow: View {
    let text: String
    var note: String?
    var tint: Color = Theme.text
    var noteTint: Color = Theme.textDim
    var isCurrent = false
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(Theme.fLabel)
                    .foregroundStyle(tint)
                    .underline(hovering && !isCurrent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let note {
                    Text(note).font(Theme.fLabel).foregroundStyle(noteTint).lineLimit(1)
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { hovering = $0 }
        .help(help ?? text)
    }
}

/// Left-aligned wrapping layout for tag pills.
struct SetsFlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowH))
    }
}

// MARK: - Header, picture, path

struct DetailHeader: View {
    let set: SetEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(set.name)
                .font(Theme.fHead)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Text(SetFormat.size(set.projectSize))
                .font(Theme.fLabel)
                .foregroundStyle(Theme.textDim)
                .help(SetsStrings.projectSizeHelp.s)
        }
    }
}

/// The arrangement picture; a click opens the preview.
struct DetailThumbnail: View {
    @Environment(AppModel.self) private var app
    let path: String
    @State private var hovering = false

    var body: some View {
        Button { app.presentPreview() } label: {
            ArrangementThumbnailView(path: path)
                .frame(height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.thumbR, style: .continuous)
                        .strokeBorder(hovering ? Theme.light.opacity(0.6) : Theme.cardBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(CommonStrings.arrangementPreview.s)
        .accessibilityLabel(CommonStrings.arrangementPreview.s)
    }
}

/// The path is itself the link (Show in Finder): it only lightens under the cursor.
struct DetailPath: View {
    @Environment(AppModel.self) private var app
    let path: String
    @State private var hovering = false

    var body: some View {
        Button { app.revealInFinder(path: path) } label: {
            Text(path)
                .font(Theme.fLabel)
                .foregroundStyle(hovering ? Theme.text : Theme.textDim)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(CommonStrings.showInFinder.s)
    }
}

// MARK: - Tags and note

/// One dim line while there are none (so the feature can be found); tag pills and the note text
/// once something has been written. A click anywhere opens the editor.
struct DetailTagsAndNote: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry
    @State private var hovering = false

    var body: some View {
        _ = app.sets.metaRevision
        let tags = app.sets.tags(of: set)
        let note = app.sets.note(of: set)
        return Button { app.presentTags() } label: {
            VStack(alignment: .leading, spacing: 8) {
                if tags.isEmpty, note.isEmpty {
                    HStack(spacing: 6) {
                        IconView(icon: .tag, size: 12)
                        Text(SetsStrings.addTagsOrNote.s).font(Theme.fBadge)
                    }
                    .foregroundStyle(hovering ? Theme.text : Theme.textDim)
                } else {
                    if !tags.isEmpty {
                        SetsFlowLayout { ForEach(tags, id: \.self) { TagPill(text: $0) } }
                    }
                    if !note.isEmpty {
                        PanelHeading(title: SetsStrings.noteHeading.s)
                        Text(note)
                            .font(Theme.fLabel)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(CommonStrings.tagsAndNotes.s)
    }
}

// MARK: - Versions and files

/// The other .als files of the same folder. The list folds them under "+3"; without this block
/// there would be nowhere to see what exactly is hidden. A click shows that version.
struct DetailVersions: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry

    var body: some View {
        let all = app.catalog.index.inSameFolder(set)
        if all.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                PanelHeading(title: SetsStrings.versionsHeading.f(all.count))
                    .padding(.bottom, 2)
                ForEach(all) { version in
                    PanelLinkRow(text: version.name, note: SetFormat.day(version.modified),
                                 tint: version.path == set.path ? Theme.text : Theme.textDim,
                                 isCurrent: version.path == set.path) {
                        app.sets.select(path: version.path)
                    }
                }
            }
        }
    }
}

struct DetailFiles: View {
    let set: SetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeading(title: SetsStrings.filesHeading.s)
            HStack {
                Text(SetsStrings.fileCount.f(set.totalRefs)).font(Theme.fLabel).foregroundStyle(Theme.text)
                Spacer()
                // Colour only when things are bad: a green zero promised an event that is not there.
                if set.missingFiles > 0 {
                    Text(SetsStrings.missingCount.f(set.missingFiles)).font(Theme.fLabel).foregroundStyle(Theme.red)
                }
            }
        }
    }
}

// MARK: - Sample folders

/// Which folders of the sample library the set takes from; a click opens the folder on the Samples tab.
struct DetailSampleFolders: View {
    @Environment(AppModel.self) private var app
    let groups: [SampleFolderGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelHeading(title: SetsStrings.sampleFoldersHeading.f(groups.count)).padding(.bottom, 2)
            ForEach(groups) { group in
                PanelLinkRow(text: group.title, note: group.count.formatted(), help: group.folder) {
                    app.samples.showFolder(group.folder)
                }
            }
        }
    }
}

// MARK: - Plugins

struct DetailPlugins: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry

    var body: some View {
        // Missing plugins are a state, not errors: one count in the heading, the names merely dimmed.
        // With no readable plugin inventory nothing is known, so nothing is marked at all.
        let known = app.sets.pluginsKnown
        VStack(alignment: .leading, spacing: 2) {
            PanelHeading(title: SetsStrings.pluginsHeading.f(set.plugins.count),
                         trailing: known && set.missingPlugins > 0 ? SetsStrings.notInstalledCount.f(set.missingPlugins) : nil)
                .padding(.bottom, 2)
            if set.plugins.isEmpty {
                Text(SetsStrings.onlyLiveDevices.s).font(Theme.fLabel).foregroundStyle(Theme.textDim)
            } else {
                let inventory = app.catalog.index.inventory
                ForEach(Array(set.plugins.enumerated()), id: \.offset) { index, name in
                    let uid = index < set.pluginUids.count ? set.pluginUids[index] : ""
                    let match = known ? inventory.match(uid: uid, name: name).kind : .exact
                    PanelLinkRow(text: name,
                                 note: match == .otherFormat ? SetsStrings.otherFormat.s : nil,
                                 tint: match == .missing ? Theme.textDim.opacity(0.7) : Theme.text,
                                 help: SetsStrings.showPluginHelp.f(name)) {
                        app.plugins.show(pluginNamed: name)
                    }
                }
                if !known {
                    Text(SetsStrings.pluginStatusUnknown.s)
                        .font(Theme.fBadge).foregroundStyle(Theme.textDim)
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Renders

struct DetailRenders: View {
    @Environment(AppModel.self) private var app
    let renders: [RenderFile]
    let path: String

    /// A project can have hundreds of bounces; the newest few are enough here (the player has the rest).
    private static let shown = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelHeading(title: SetsStrings.rendersHeading.f(renders.count)).padding(.bottom, 2)
            ForEach(renders.prefix(Self.shown)) { render in
                PanelLinkRow(text: render.name, note: render.ext, help: SetsStrings.playRenderHelp.s) {
                    app.sets.playRender(of: path)
                }
            }
            if renders.count > Self.shown {
                Text(SetsStrings.moreItems.f(renders.count - Self.shown))
                    .font(Theme.fLabel).foregroundStyle(Theme.textDim)
            }
        }
    }
}
