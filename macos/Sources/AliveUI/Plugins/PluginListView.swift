// Port of the plugins grid in src/MainForm.cs (FillPlugins + the list control): pill rows, sortable
// headings, keyboard navigation. A custom list rather than `Table` so a row can be scrolled to
// (`show(pluginNamed:)`), styled like upstream's, and moved with the arrow keys.
import SwiftUI
import AliveCore

/// Column widths; the plugin's name takes the rest.
private enum Col {
    static let developer: CGFloat = 150
    static let type: CGFloat = 120
    static let format: CGFloat = 84
    static let sets: CGFloat = 52
    static let lastUsed: CGFloat = 100
    static let status: CGFloat = 116
    static let gap: CGFloat = 12
}

struct PluginListView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        let model = app.plugins
        let rows = model.rows
        VStack(spacing: 4) {
            PluginHeaderRow()
            if rows.isEmpty {
                emptyState(model)
            } else {
                list(rows, model)
            }
        }
    }

    @ViewBuilder private func emptyState(_ model: PluginsModel) -> some View {
        if !model.hasCatalogPlugins {
            if app.catalog.isScanning || !app.catalog.isLoaded {
                EmptyState(icon: .refresh, title: CommonStrings.scanning.s)
            } else {
                EmptyState(icon: .nebula, title: PluginsStrings.noPluginsTitle.s, message: PluginsStrings.noPluginsBody.s)
            }
        } else {
            EmptyState(icon: .magnifier, title: PluginsStrings.noMatchTitle.s, message: PluginsStrings.noMatchBody.s)
        }
    }

    private func list(_ rows: [PluginRow], _ model: PluginsModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        PluginRowView(row: row, isSelected: model.selectedID == row.id, listFocused: focused)
                            .id(row.id)
                            .onTapGesture(count: 2) { model.selectedID = row.id; model.reveal(row) }
                            .onTapGesture { model.selectedID = row.id; focused = true }
                            .contextMenu { PluginRowMenu(row: row) }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
            .onKeyPress(.pageUp) { model.moveSelection(by: -10); return .handled }
            .onKeyPress(.pageDown) { model.moveSelection(by: 10); return .handled }
            .onKeyPress(.home) { model.moveSelection(by: nil); return .handled }
            .onKeyPress(.end) { model.moveSelection(by: nil, toEnd: true); return .handled }
            .onKeyPress(.return) {
                guard let row = model.selectedRow else { return .ignored }
                model.reveal(row)
                return .handled
            }
            .onChange(of: model.pendingScrollID) { _, id in scroll(proxy, model, to: id) }
            .onAppear { scroll(proxy, model, to: model.pendingScrollID) }
            .accessibilityLabel(PluginsStrings.title.s)
        }
    }

    /// `show(pluginNamed:)` and the arrow keys ask for a row; the row may not exist yet when the
    /// tab has just been switched, hence the deferred hop.
    private func scroll(_ proxy: ScrollViewProxy, _ model: PluginsModel, to id: String?) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(Theme.selectAnimation) { proxy.scrollTo(id, anchor: .center) }
            model.pendingScrollID = nil
        }
    }
}

// MARK: - Header

private struct PluginHeaderRow: View {
    var body: some View {
        HStack(spacing: Col.gap) {
            HeaderCell(column: .name).frame(maxWidth: .infinity, alignment: .leading)
            HeaderCell(column: .vendor).frame(width: Col.developer, alignment: .leading)
            HeaderCell(column: .fxType).frame(width: Col.type, alignment: .leading)
            HeaderCell(column: .format).frame(width: Col.format, alignment: .leading)
            HeaderCell(column: .sets).frame(width: Col.sets, alignment: .trailing)
            HeaderCell(column: .lastUsed).frame(width: Col.lastUsed, alignment: .leading)
            HeaderCell(column: .status).frame(width: Col.status, alignment: .trailing)
        }
        .padding(.horizontal, Theme.cellPadX)
        .frame(height: 30)
    }
}

private struct HeaderCell: View {
    @Environment(AppModel.self) private var app
    let column: PluginColumn

    var body: some View {
        let model = app.plugins
        let sorted = model.sortColumn == column
        Button {
            model.toggleSort(column)
        } label: {
            HStack(spacing: 4) {
                Text(PluginsFormat.column(column))
                if sorted {
                    IconView(icon: model.sortAscending ? .sortUp : .sortDown, size: 9, weight: .bold)
                }
            }
        }
        .buttonStyle(HeaderButtonStyle(isSorted: sorted))
        .accessibilityLabel(PluginsStrings.sortBy.f(PluginsFormat.column(column)))
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    let isSorted: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(isSorted: isSorted, configuration: configuration)
    }

    private struct Styled: View {
        let isSorted: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fLabel)
                .foregroundStyle(configuration.isPressed ? Theme.lightPressed
                                 : isSorted || hovering ? Theme.text : Theme.textDim)
                .lineLimit(1)
                .focusRing(isFocused, cornerRadius: 6)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Theme.hoverAnimation, value: hovering)
        }
    }
}

// MARK: - Rows

private struct PluginRowView: View {
    let row: PluginRow
    let isSelected: Bool
    let listFocused: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Col.gap) {
            HStack(spacing: 10) {
                RoleGlyph(role: row.role)
                Text(row.name)
                    .font(Theme.fTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            cell(row.vendor, width: Col.developer)
            cell(PluginsFormat.type(row), width: Col.type)
            cell(row.format, width: Col.format)
            Text(PluginsFormat.sets(row.sets))
                .monospacedDigit()
                .foregroundStyle(row.sets > 0 ? Theme.text : Theme.textDim)
                .frame(width: Col.sets, alignment: .trailing)
            cell(PluginsFormat.lastUsed(row.lastUsed), width: Col.lastUsed)
            StatusMark(status: row.status)
                .frame(width: Col.status, alignment: .trailing)
        }
        .font(Theme.fBody)
        .padding(.horizontal, Theme.cellPadX)
        .frame(height: Theme.rowPillH)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowPillH / 2, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.06) : hovering ? Theme.rowHover : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowPillH / 2, style: .continuous)
                .strokeBorder(isSelected ? (listFocused ? Theme.focus : Theme.text.opacity(0.7)) : .clear, lineWidth: 1)
        )
        .frame(height: Theme.rowH)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }
}

/// Instrument or effect, as a small glyph before the name.
private struct RoleGlyph: View {
    let role: PluginRole

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .frame(width: 16)
            .opacity(role == .unknown ? 0.35 : 1)
            .help(PluginsFormat.role(role))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch role {
        case .instrument: return "pianokeys"
        case .effect: return "slider.horizontal.3"
        case .unknown: return "puzzlepiece.extension"
        }
    }
}

/// A green check when installed; a dimmed badge otherwise — a state, not an error.
private struct StatusMark: View {
    let status: PluginStatus

    var body: some View {
        switch status {
        case .installed:
            IconView(icon: .check, size: 13, weight: .bold)
                .foregroundStyle(Theme.green)
                .help(PluginsFormat.status(status))
        case .otherFormat, .missing:
            TagPill(text: PluginsFormat.status(status))
        case .unknown:
            Text("—").foregroundStyle(Theme.textDim)
        }
    }
}

private struct PluginRowMenu: View {
    @Environment(AppModel.self) private var app
    let row: PluginRow

    var body: some View {
        let model = app.plugins
        Button(CommonStrings.showInFinder.s) { model.reveal(row) }
            .disabled(row.path.isEmpty)
        Button(PluginsStrings.copyName.s) { model.copy(row.name) }
        Button(PluginsStrings.copyPath.s) { model.copy(row.path) }
            .disabled(row.path.isEmpty)
    }
}
