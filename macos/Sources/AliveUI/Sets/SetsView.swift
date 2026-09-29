// Mac-only: Sets tab, minimal list (wave 1.5). The Sets implementer replaces the table with the
// full one (configurable columns, inspector, filters). Keeps the contract: selection lives in
// `app.selectedSetPath`; Return / double-click opens in Live.
import SwiftUI
import AliveCore

struct SetsView: View {
    @Environment(AppModel.self) private var app
    @State private var sortOrder = [KeyPathComparator(\SetEntry.modified, order: .reverse)]

    var body: some View {
        if !app.catalog.hasEnabledRoots {
            RootsEmptyState()
        } else if app.catalog.sets.isEmpty {
            emptyCatalog
        } else {
            SetsTable(rows: app.sets.rows.sorted(using: sortOrder), sortOrder: $sortOrder)
        }
    }

    @ViewBuilder private var emptyCatalog: some View {
        if app.catalog.isScanning || !app.catalog.isLoaded {
            EmptyState(icon: .refresh, title: CommonStrings.scanning.s)
        } else {
            EmptyState(icon: .folder, title: CommonStrings.noSetsTitle.s, message: CommonStrings.noSetsBody.s)
        }
    }
}

private struct SetsTable: View {
    @Environment(AppModel.self) private var app
    let rows: [SetEntry]
    @Binding var sortOrder: [KeyPathComparator<SetEntry>]

    var body: some View {
        @Bindable var app = app
        Table(rows, selection: $app.selectedSetPath, sortOrder: $sortOrder) {
            TableColumn(SetsStrings.colName.s, value: \.name) { set in
                NameCell(set: set)
            }
            .width(min: 180, ideal: 320)
            TableColumn(SetsStrings.colModified.s, value: \.modified) { set in
                Text(SetFormat.modified(set.modified))
            }
            .width(min: 120, ideal: 150)
            TableColumn(SetsStrings.colBPM.s, value: \.tempo) { set in
                Text(SetFormat.tempo(set.tempo))
            }
            .width(min: 50, ideal: 70)
            TableColumn(SetsStrings.colPlugins.s, value: \.plugins.count) { set in
                Text(SetFormat.count(set.plugins.count))
            }
            .width(min: 60, ideal: 80)
            TableColumn(SetsStrings.colFiles.s, value: \.projectFiles) { set in
                Text(SetFormat.count(set.projectFiles))
            }
            .width(min: 60, ideal: 80)
            TableColumn(SetsStrings.colProjectSize.s, value: \.projectSize) { set in
                Text(SetFormat.size(set.projectSize))
            }
            .width(min: 80, ideal: 110)
        }
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            if let path = ids.first {
                Button(CommonStrings.openInLive.s) { app.openInLive(path: path) }
                Button(CommonStrings.showInFinder.s) { app.revealInFinder(path: path) }
            }
        } primaryAction: { ids in
            if let path = ids.first { app.openInLive(path: path) }
        }
        .onKeyPress(.return) {
            guard app.hasSelectedSet else { return .ignored }
            app.openSelectedInLive()
            return .handled
        }
    }
}

private struct NameCell: View {
    let set: SetEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(set.name)
                .lineLimit(1)
            if set.collapsedCount > 0 {
                TagPill(text: SetsStrings.moreVersions.f(set.collapsedCount))
            }
            if !set.projectName.isEmpty, set.projectName != set.name {
                Text(set.projectName)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
    }
}
