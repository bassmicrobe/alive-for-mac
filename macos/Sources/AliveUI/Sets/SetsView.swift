// Mac-only: the Sets tab — list on the left, inspector on the right (upstream: MainForm's Sets
// mode + DetailPanel). Selection lives in `app.selectedSetPath`; Return / double-click opens in
// Live, Space plays the render.
import SwiftUI
import AliveCore

struct SetsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.catalog.hasEnabledRoots {
            RootsEmptyState()
        } else if app.catalog.sets.isEmpty {
            emptyCatalog
        } else {
            HStack(alignment: .top, spacing: Theme.panelGap) {
                listColumn
                DetailPanel()
                    .frame(width: Theme.panelW)
            }
            .padding(.leading, Theme.pad)
            .padding(.trailing, Theme.pad)
            .padding(.bottom, Theme.pad)
        }
    }

    @ViewBuilder private var listColumn: some View {
        let pipeline = app.sets.pipeline
        VStack(spacing: 8) {
            SetsListStrip()
            if pipeline.heads.isEmpty {
                noMatches
            } else {
                SetsTable(pipeline: pipeline)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
            }
        }
    }

    @ViewBuilder private var emptyCatalog: some View {
        if app.catalog.isScanning || !app.catalog.isLoaded {
            EmptyState(icon: .refresh, title: CommonStrings.scanning.s)
        } else {
            EmptyState(icon: .folder, title: CommonStrings.noSetsTitle.s, message: CommonStrings.noSetsBody.s)
        }
    }

    /// Everything was filtered or searched away: say so, and offer the way back.
    private var noMatches: some View {
        VStack(spacing: 14) {
            EmptyState(icon: .magnifier, title: SetsStrings.noMatchesTitle.s, message: SetsStrings.noMatchesBody.s)
            if !app.sets.filter.isEmpty {
                PillButton(title: SetsStrings.clearFilters.s, icon: .filters) { app.sets.filter.clear() }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The thin bar above the table: "pinned first" and the column reset.
private struct SetsListStrip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            PinnedFirstToggle(isOn: app.settings.pinnedFirst) { app.sets.setPinnedFirst($0) }
            Spacer(minLength: 8)
            if app.sets.activeFilterCount > 0 {
                StripButton(title: SetsStrings.clearFilters.s, icon: .close) { app.sets.filter.clear() }
            }
            StripButton(title: SetsStrings.resetColumns.s, help: SetsStrings.resetColumnsHelp.s) {
                app.sets.resetColumns()
            }
        }
        .frame(height: 26)
    }
}

private struct PinnedFirstToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Button { set(!isOn) } label: {
            HStack(spacing: 6) {
                IconView(icon: isOn ? .starFill : .star, size: 10)
                Text(SetsStrings.pinnedFirst.s)
            }
            .font(Theme.fSmall)
            .foregroundStyle(isOn ? Theme.onLight : hovering ? Theme.text : Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(isOn ? AnyShapeStyle(Theme.light)
                        : AnyShapeStyle(hovering ? Theme.surfaceHover : Theme.surface), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(SetsStrings.pinnedFirstHelp.s)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct StripButton: View {
    let title: String
    var icon: AppIcon?
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { IconView(icon: icon, size: 9) }
                Text(title)
            }
            .font(Theme.fSmall)
            .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(help ?? title)
    }
}
