// Mac-only: the sets table (upstream: RowListView in MainForm's Sets mode). Configurable columns
// through `TableColumnCustomization`, folded versions as disclosure rows, keyboard and context menu.
import SwiftUI
import AliveCore

struct SetsTable: View {
    @Environment(AppModel.self) private var app
    let pipeline: SetsPipeline

    var body: some View {
        @Bindable var app = app
        @Bindable var sets = app.sets
        let versionRows = Set(pipeline.hidden.values.joined().map(\.path))
        Table(of: SetEntry.self, selection: $app.selectedSetPath,
              sortOrder: $sets.sortOrder, columnCustomization: $sets.columnCustomization) {
            Group {
                TableColumn(SetColumnID.set.title.s, sortUsing: SetSortComparator(.set)) { set in
                    SetNameCell(set: set, isVersionRow: versionRows.contains(set.path))
                }
                .width(min: 200, ideal: 340)
                .customizationID(SetColumnID.set.id)
                .disabledCustomizationBehavior(.visibility)

                column(.place) { SetTextCell(text: $0.place, dim: true) }
                column(.modified) { SetTextCell(text: SetFormat.day($0.modified)) }
                column(.created) { SetTextCell(text: SetFormat.day($0.created), dim: true) }
                column(.live) { SetTextCell(text: $0.shortVersion, dim: true) }
                column(.bpm) { SetTextCell(text: SetFormat.tempo($0.tempo), right: true) }
            }
            Group {
                column(.key) { SetTextCell(text: $0.key) }
                column(.tracks) { SetTextCell(text: SetFormat.count($0.tracks), right: true) }
                column(.pluginCount) { SetTextCell(text: SetFormat.count($0.plugins.count), right: true, dim: true) }
                column(.fileCount) { SetTextCell(text: SetFormat.count($0.totalRefs), right: true, dim: true) }
                column(.pluginsMissed) { PluginsMissedCell(set: $0) }
                column(.filesMissed) {
                    MissingMark(total: $0.totalRefs, missing: $0.missingFiles, unreadable: !$0.error.isEmpty)
                }
            }
            Group {
                column(.tags) { SetTagsCell(set: $0) }
                column(.size) { SetTextCell(text: SetFormat.size($0.projectSize), right: true) }
            }
        } rows: {
            ForEach(pipeline.heads) { head in
                let kids = pipeline.hidden[SetsPipeline.key(forDirectory: head.directory)] ?? []
                if kids.isEmpty {
                    TableRow(head)
                } else {
                    DisclosureTableRow(head, isExpanded: expansion(of: head)) {
                        ForEach(kids) { TableRow($0) }
                    }
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .tint(SetsStyle.selection)
        .foregroundStyle(Theme.text)
        .contextMenu(forSelectionType: String.self) { paths in
            SetContextMenu(paths: paths)
        } primaryAction: { paths in
            if let path = paths.first { app.openInLive(path: path) }
        }
        .onKeyPress(.space) {
            guard let path = app.selectedSetPath else { return .ignored }
            app.sets.playRender(of: path)
            return .handled
        }
        .onKeyPress(.return) {
            guard app.hasSelectedSet else { return .ignored }
            app.openSelectedInLive()
            return .handled
        }
        .background(TableScrollBridge(request: app.sets.scrollRequest, rows: pipeline.flattened(expanded: app.sets.expandedDirs)))
    }

    /// One configurable, sortable column (everything but the name).
    private func column<Content: View>(_ id: SetColumnID,
                                       @ViewBuilder content: @escaping (SetEntry) -> Content) -> some TableColumnContent<SetEntry, SetSortComparator> {
        let width = id.width ?? (60, 100)
        return TableColumn(id.title.s, sortUsing: SetSortComparator(id), content: content)
            .width(min: width.min, ideal: width.ideal)
            .alignment(id.isRightAligned ? .trailing : .leading)
            .customizationID(id.id)
            .defaultVisibility(id.isDefault ? .automatic : .hidden)
    }

    private func expansion(of head: SetEntry) -> Binding<Bool> {
        Binding(get: { app.sets.isExpanded(head.directory) },
                set: { app.sets.setExpanded(head.directory, $0) })
    }
}

enum SetsStyle {
    /// The row highlight: a raised grey rather than the system accent (upstream: a light pill).
    static let selection = Color(hex: 0x4A4A52)
}

/// The right-click menu: works on the clicked row (which becomes the selection first, so the
/// shared `app.present*` actions see it).
struct SetContextMenu: View {
    @Environment(AppModel.self) private var app
    let paths: Set<String>

    var body: some View {
        if let path = paths.first {
            let hasRenders = app.sets.set(at: path)?.hasRenders ?? false
            Button(CommonStrings.openInLive.s) { app.openInLive(path: path) }
            Button(CommonStrings.showInFinder.s) { app.revealInFinder(path: path) }
            Divider()
            Button(SetsStrings.playRender.s) { app.sets.playRender(of: path) }
                .disabled(!hasRenders)
            Button(CommonStrings.arrangementPreview.s) { act(path) { app.presentPreview() } }
            Divider()
            Button(CommonStrings.tagsAndNotes.s) { act(path) { app.presentTags() } }
            Button(app.home.isPinned(path) ? SetsStrings.unpin.s : SetsStrings.pin.s) {
                app.home.togglePin(path: path)
            }
            Divider()
            Button(CommonStrings.rescue.s) { act(path) { app.presentRescue() } }
            Button(CommonStrings.exportSet.s) { act(path) { app.presentExport() } }
        }
    }

    private func act(_ path: String, _ body: () -> Void) {
        app.selectedSetPath = path
        body()
    }
}
