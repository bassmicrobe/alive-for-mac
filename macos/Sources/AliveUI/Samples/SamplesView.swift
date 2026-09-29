// Port of the Samples tab layout (src/SamplesTab.cs + the sample panel of src/DetailPanel.cs):
// lenses and columns on top, the library as a folder tree or a flat list, the panel on the right.
import SwiftUI
import AliveCore

struct SamplesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.samples
        Group {
            if model.hasEnabledRoots {
                SamplesContent(model: model)
            } else {
                SamplesEmptyState(model: model)
            }
        }
        .task {
            if !model.started { model.expandsRootsOnFirstLoad = true }
            model.start()
            model.syncRoots()      // a no-op when nothing changed; catches edits made from other tabs
        }
        .onChange(of: model.effectiveRoots) { _, _ in model.syncRoots() }
        .onDisappear { model.leave() }
    }
}

private struct SamplesContent: View {
    let model: SamplesModel
    /// Roots whose single-folder chain was already opened, so a folder the person closes stays closed.
    @State private var chained = Set<String>()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                SamplesBar(model: model)
                SamplesListArea(model: model)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            SamplesPanel(model: model)
                .frame(width: Theme.panelW)
        }
        .padding(.leading, Theme.pad)
        .padding(.trailing, Theme.pad)
        .padding(.bottom, Theme.pad)
        .task(id: model.indexGeneration) { openSingleFolderChains() }
    }

    /// A root that holds nothing but one folder ("Splice" > "sounds" > …) would leave the list two
    /// rows long and the rest of the tab empty: open such chains down to the first folder that
    /// has files or branches.
    private func openSingleFolderChains() {
        guard model.lens == .all else { return }
        let index = model.index
        for root in index.roots {
            let start = index.folders[root]
            guard model.isOpen(start.path), chained.insert(start.path.lowercased()).inserted else { continue }
            var folder = start
            while folder.files.isEmpty, folder.children.count == 1 {
                let child = index.folders[folder.children[0]]
                if !model.isOpen(child.path) { model.toggleFolder(child.path) }
                folder = child
            }
        }
    }
}

/// Lenses, the counter and progress, the column menu.
private struct SamplesBar: View {
    @Bindable var model: SamplesModel

    var body: some View {
        HStack(spacing: 12) {
            PillTabs(items: SampleLens.allCases.map { PillTabItem(value: $0, title: SampleFormat.title(of: $0)) },
                     selection: $model.lens)
                .fixedSize()
                .help(SamplesStrings.lensHelp.s)
            Spacer(minLength: 8)
            counter
            columnsMenu
        }
        .padding(.bottom, 12)
    }

    /// The text itself lives in the toolbar (`SamplesModel.shownLabel`); only the progress spinner is here.
    @ViewBuilder private var counter: some View {
        if model.isScanning && model.isManualScan { ProgressView().controlSize(.small).scaleEffect(0.7) }
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(SampleColumn.allCases.filter { $0 != SampleColumn.mandatory }, id: \.self) { c in
                Button {
                    model.toggleColumn(c)
                } label: {
                    if model.columnSpec.order.contains(c) { Label(title(c), systemImage: "checkmark") } else { Text(title(c)) }
                }
            }
        } label: {
            IconView(icon: .viewList)
                .frame(width: Theme.iconSize, height: Theme.iconSize)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .foregroundStyle(Theme.text)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(SamplesStrings.columnsMenu.s)
        .accessibilityLabel(SamplesStrings.columnsMenu.s)
    }

    private func title(_ c: SampleColumn) -> String {
        SampleFormat.title(of: c, lens: model.lens, isFlat: model.isFlat)
    }
}
