// Mac-only: the list of the Samples tab — column headings, rows, keyboard. Upstream draws this in
// RowListView (src/RowListView.cs); the row logic is in SampleLister/SamplesModel.
import SwiftUI
import AliveCore

/// How wide each column is: fixed for the numbers and dates, the name and the location share the
/// rest. Upstream's widths are pixels at 96 dpi; a point is 0.8 of one.
struct SampleColumnLayout {
    let columns: [SampleColumn]
    let spec: SampleColumnSpec

    func width(_ c: SampleColumn) -> CGFloat? {
        let w = spec.width(of: c)
        return w == 0 ? nil : CGFloat(w) * 0.8
    }
}

struct SamplesListArea: View {
    let model: SamplesModel
    @FocusState private var focused: Bool

    var body: some View {
        let listing = model.listing
        let layout = SampleColumnLayout(columns: model.visibleColumns, spec: model.columnSpec)
        VStack(spacing: 0) {
            SampleHeaderRow(model: model, layout: layout)
            if listing.rows.isEmpty {
                placeholder
            } else {
                rows(listing.rows, layout: layout)
            }
        }
    }

    // MARK: rows

    private func rows(_ rows: [SampleRow], layout: SampleColumnLayout) -> some View {
        let cells = SampleCells(index: model.index, usage: model.usage, copies: model.copies, unknown: model.usageUnknown)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        SampleRowView(model: model, row: row, layout: layout, cells: cells)
                            .id(row.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(Theme.selectAnimation) { proxy.scrollTo(target.id, anchor: .center) }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press) }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: model.moveSelection(by: -1)
        case .downArrow: model.moveSelection(by: 1)
        case .rightArrow: return model.treeKey(open: true) ? .handled : .ignored
        case .leftArrow: return model.treeKey(open: false) ? .handled : .ignored
        case .space: model.togglePlaySelected()
        case .return:
            guard let id = model.selection, let row = model.listing.rows.first(where: { $0.id == id }) else { return .ignored }
            if press.modifiers.contains(.shift) {
                model.app.revealInFinder(path: id)
            } else {
                model.activate(row)
            }
        default: return .ignored
        }
        return .handled
    }

    // MARK: nothing to list

    @ViewBuilder private var placeholder: some View {
        if !model.isLoaded || model.isScanning {
            EmptyState(icon: .refresh, title: SamplesStrings.indexing.s)
        } else if model.index.files.isEmpty {
            EmptyState(icon: .wave, title: SamplesStrings.noSamplesTitle.s, message: SamplesStrings.noSamplesBody.s)
        } else {
            EmptyState(icon: .magnifier, title: SamplesStrings.noSamplesTitle.s)
        }
    }
}

// MARK: - Headings

private struct SampleHeaderRow: View {
    let model: SamplesModel
    let layout: SampleColumnLayout

    var body: some View {
        HStack(spacing: 0) {
            ForEach(layout.columns, id: \.self) { c in
                HeaderCell(model: model, column: c, width: layout.width(c))
            }
        }
        .padding(.horizontal, Theme.cellPadX)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct HeaderCell: View {
    let model: SamplesModel
    let column: SampleColumn
    let width: CGFloat?
    @State private var hovering = false

    var body: some View {
        Button {
            model.sortBy(column)
        } label: {
            HStack(spacing: 4) {
                if column.isRightAligned { Spacer(minLength: 0) }
                Text(SampleFormat.title(of: column, lens: model.lens, isFlat: model.isFlat))
                    .lineLimit(1)
                if model.sort.column == column {
                    IconView(icon: model.sort.descending ? .sortDown : .sortUp, size: 8, weight: .bold)
                }
                if !column.isRightAligned { Spacer(minLength: 0) }
            }
            .font(Theme.fLabel)
            .foregroundStyle(hovering || model.sort.column == column ? Theme.text : Theme.textDim)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .accessibilityAddTraits(.isButton)
    }
}

extension SamplesModel {
    /// A click on a heading: that column, ascending; again, descending. (Upstream `SortSamplesBy`.)
    func sortBy(_ column: SampleColumn) {
        sort = sort.column == column ? SampleSort(column: column, descending: !sort.descending)
                                     : SampleSort(column: column, descending: false)
    }
}
