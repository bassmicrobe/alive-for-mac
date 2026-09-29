// Port of the set half of src/DetailPanel.cs: the inspector on the right of the Sets tab.
// A card with the selected set's details, a scrolling column of sections, and the primary action
// pinned to the bottom.
import SwiftUI
import AliveCore

struct DetailPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let path = app.selectedSetPath, let set = app.sets.set(at: path) {
                SetDetail(set: set)
            } else {
                EmptyState(icon: .viewList, title: SetsStrings.detailEmptyTitle.s,
                           message: SetsStrings.detailEmptyBody.s)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .animation(Theme.hoverAnimation, value: app.selectedSetPath)
    }
}

/// What is loaded off the main thread for the shown set.
private struct DetailExtras {
    var renders: [RenderFile] = []
    var sampleFolders: [SampleFolderGroup] = []
}

private struct SetDetail: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry
    @State private var extras = DetailExtras()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DetailHeader(set: set)
                    DetailThumbnail(path: set.path)
                    DetailPath(path: set.path)
                    DetailTagsAndNote(set: set)
                    DetailVersions(set: set)
                    DetailFiles(set: set)
                    if !extras.sampleFolders.isEmpty { DetailSampleFolders(groups: extras.sampleFolders) }
                    if !set.error.isEmpty {
                        Text(set.error).font(Theme.fLabel).foregroundStyle(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DetailPlugins(set: set)
                    if !extras.renders.isEmpty { DetailRenders(renders: extras.renders, path: set.path) }
                }
                .padding(Theme.panelPad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            DetailFooter(set: set)
        }
        .task(id: "\(set.path)|\(set.modified.timeIntervalSince1970)|\(app.catalog.revision)") {
            await load()
        }
    }

    /// Renders come from the disk and the sample folders from grouping hundreds of paths: keep
    /// both out of `body`.
    private func load() async {
        let entry = set
        let roots = SampleFolderGroups.roots(env: app.catalog.env, sampleRoots: app.settings.sampleRoots,
                                             disabled: app.settings.disabledSampleRoots)
        let result = await Task.detached(priority: .userInitiated) {
            DetailExtras(renders: RenderScan.find(entry),
                         sampleFolders: SampleFolderGroups.make(samples: entry.samples, roots: roots))
        }.value
        guard !Task.isCancelled else { return }
        extras = result
    }
}

// MARK: - Footer

private struct DetailFooter: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry

    var body: some View {
        HStack(spacing: 8) {
            Button { app.openInLive(path: set.path) } label: {
                Text(CommonStrings.openInLive.s).frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .help(CommonStrings.openInLive.s)

            Menu {
                Button(CommonStrings.showInFinder.s) { app.revealInFinder(path: set.path) }
                Button(CommonStrings.tagsAndNotes.s) { app.presentTags() }
                Divider()
                Button(CommonStrings.rescue.s) { app.presentRescue() }
                Button(CommonStrings.exportSet.s) { app.presentExport() }
            } label: {
                IconView(icon: .hiddenBtnsOpen, size: 12)
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(Theme.text)
                    .frame(width: Theme.iconSize, height: Theme.iconSize)
                    .background(Theme.surfaceHover, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(SetsStrings.moreActions.s)
            .accessibilityLabel(SetsStrings.moreActions.s)
        }
        .padding(Theme.panelPad)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
    }
}
