// Port of src/DetailPanel.cs ShowPlugin / PaintPlugin: the selected plugin's facts and the sets that
// use it. A click on a set opens it on the Sets tab (upstream OnSetRequested).
import SwiftUI
import AliveCore

struct PluginDetailPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.plugins
        SurfaceCard(padding: 0) {
            if let row = model.selectedRow {
                Detail(row: row, sets: model.selectedSets)
            } else {
                Text(PluginsStrings.selectPrompt.s)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(Theme.panelPad * 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Theme.panelW)
    }
}

private struct Detail: View {
    @Environment(AppModel.self) private var app
    let row: PluginRow
    let sets: [SetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            facts
            if !row.path.isEmpty { fileBlock }
            Divider().overlay(Theme.hairline)
            setsBlock
        }
        .padding(Theme.panelPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(Theme.fHead)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !row.vendor.isEmpty {
                Text(row.vendor).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var facts: some View {
        VStack(spacing: 6) {
            Fact(PluginsStrings.detailStatus.s, PluginsFormat.status(row.status), tone: statusTone)
            Fact(PluginsStrings.detailFormat.s, row.format)
            Fact(PluginsStrings.detailKind.s, PluginsFormat.role(row.role))
            Fact(PluginsStrings.detailVersion.s, row.version)
            Fact(PluginsStrings.detailCategory.s, PluginsFormat.category(row.stat.installed?.category ?? ""))
            Fact(PluginsStrings.detailUsedIn.s, row.sets > 0 ? PluginsFormat.setsPhrase(row.sets) : "")
            Fact(PluginsStrings.detailLastUsed.s, row.lastUsed == nil ? "" : PluginsFormat.lastUsed(row.lastUsed))
        }
        .font(Theme.fBody)
    }

    private var statusTone: Color {
        switch row.status {
        case .installed: return Theme.green
        case .otherFormat, .missing, .unknown: return Theme.secondaryText
        }
    }

    private var fileBlock: some View {
        Button {
            app.plugins.reveal(row)
        } label: {
            Text(row.path)
                .font(Theme.fLabel)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PathButtonStyle())
        .help(CommonStrings.showInFinder.s)
        .accessibilityLabel("\(CommonStrings.showInFinder.s): \(row.path)")
    }

    private var setsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(PluginsStrings.detailSetsHeader.f(sets.count))
            if sets.isEmpty {
                Text(PluginsStrings.noSetsUse.s).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sets) { set in SetLink(set: set) }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "Label:      value" with the value right-aligned; a fact with no value is left out.
private struct Fact: View {
    let label: String
    let value: String
    var tone: Color = Theme.text

    init(_ label: String, _ value: String, tone: Color = Theme.text) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(tone).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
    }
}

private struct SetLink: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry

    var body: some View {
        Button {
            app.plugins.openSet(path: set.path)
        } label: {
            HStack {
                Text(set.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
            }
            .frame(minHeight: 26)
        }
        .buttonStyle(SetLinkStyle())
        .help(set.name + "\n" + set.path)
    }
}

private struct SetLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fBody)
                .foregroundStyle(configuration.isPressed ? Theme.lightPressed : hovering ? Color.white : Theme.text)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Theme.rowHover : .clear)
                )
                .focusRing(isFocused, cornerRadius: 8)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Theme.hoverAnimation, value: hovering)
        }
    }
}

private struct PathButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : hovering ? 1 : 0.85)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Theme.rowHover : .clear)
                )
                .focusRing(isFocused, cornerRadius: 8)
                .padding(-6)
                .onHover { hovering = $0 }
                .animation(Theme.hoverAnimation, value: hovering)
        }
    }
}
