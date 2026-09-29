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

    private var counter: some View {
        HStack(spacing: 8) {
            if model.isScanning && model.isManualScan { ProgressView().controlSize(.small).scaleEffect(0.7) }
            Text(counterText)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .animation(Theme.hoverAnimation, value: counterText)
    }

    private var counterText: String { model.shownLabel }

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
