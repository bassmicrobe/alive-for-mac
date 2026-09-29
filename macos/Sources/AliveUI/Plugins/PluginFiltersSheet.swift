// Port of src/PluginFiltersDialog.cs: status, format, type, developer and sets count. Conditions
// apply live — the list and the "N shown" counter behind the sheet change as you click — and a
// choice that could not match anything under the other conditions is dimmed.
import SwiftUI
import AliveCore

struct PluginFiltersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = app.plugins
        let facets = model.facets
        let stats = model.allStats
        SheetFrame(title: PluginsStrings.filtersTitle.s, width: 640) {
            VStack(alignment: .leading, spacing: 16) {
                row(PluginsStrings.filterStatus.s) { statusPills($model, facets) }
                row(PluginsStrings.filterFormat.s) { formatPills($model, facets) }
                row(PluginsStrings.filterType.s) {
                    ChipPicker(placeholder: PluginsStrings.filterAnyType.s,
                               options: PluginFacets.categoryOptions(stats),
                               selection: $model.filter.categories,
                               isReachable: facets.canPick(category:),
                               label: PluginsFormat.categoryLabel)
                }
                row(PluginsStrings.filterDeveloper.s) {
                    ChipPicker(placeholder: PluginsStrings.filterAnyDeveloper.s,
                               options: PluginFacets.vendorOptions(stats),
                               selection: $model.filter.vendors,
                               isReachable: facets.canPick(vendor:),
                               label: PluginsFormat.vendorLabel)
                }
                row(PluginsStrings.filterSetsCount.s) {
                    HStack(spacing: 12) {
                        BoundField(placeholder: PluginsStrings.filterFrom.s, value: $model.filter.setsMin)
                        BoundField(placeholder: PluginsStrings.filterTo.s, value: $model.filter.setsMax)
                    }
                }
                footer(facets)
            }
        }
        .onExitCommand { dismiss() }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .frame(width: 110, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusPills(_ model: Bindable<PluginsModel>, _ facets: PluginFacets) -> some View {
        HStack(spacing: 8) {
            FilterPill(title: PluginsStrings.statusInstalled.s, count: facets.installed, isOn: model.filter.statusInstalled)
            FilterPill(title: PluginsStrings.statusNotInstalled.s, count: facets.missing, isOn: model.filter.statusMissing)
            FilterPill(title: PluginsStrings.statusOtherFormat.s, count: facets.otherFormat, isOn: model.filter.statusOtherFormat)
        }
    }

    private func formatPills(_ model: Bindable<PluginsModel>, _ facets: PluginFacets) -> some View {
        HStack(spacing: 8) {
            ForEach(PluginFilter.formatNames, id: \.self) { name in
                FilterPill(title: PluginsFormat.formatLabel(name), count: facets.formatCounts[name] ?? 0,
                           isOn: formatBinding(model, name))
            }
        }
    }

    private func formatBinding(_ model: Bindable<PluginsModel>, _ name: String) -> Binding<Bool> {
        Binding(
            get: { model.wrappedValue.filter.formats.contains(name) },
            set: { on in
                if on { model.wrappedValue.filter.formats.insert(name) } else { model.wrappedValue.filter.formats.remove(name) }
            })
    }

    private func footer(_ facets: PluginFacets) -> some View {
        HStack(spacing: 10) {
            Text(PluginsStrings.filterMatches.f(facets.matches))
                .font(Theme.fBody)
                .foregroundStyle(facets.matches == 0 ? Theme.red : Theme.textDim)
            Spacer()
            PillButton(title: PluginsStrings.filterReset.s) { app.plugins.filter.clear() }
                .disabled(app.plugins.filter.isEmpty)
            PillButton(title: CommonStrings.done.s, kind: .primary) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }
}
