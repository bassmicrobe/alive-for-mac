// Port of src/FiltersDialog.cs: every filter condition in one window. Conditions apply live (the
// list behind the sheet follows), and the number of sets that still pass is always in view.
import SwiftUI
import AliveCore

struct FiltersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var facets = SetFilterFacets()

    var body: some View {
        @Bindable var sets = app.sets
        SheetFrame(title: SetsStrings.filtersTitle.s, width: 660, height: 640) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    row(SetsStrings.fltModified.s) {
                        HStack(spacing: 10) {
                            DateFilterField(cue: SetsStrings.fltFrom.s, upperBound: false, date: $sets.filter.from)
                            DateFilterField(cue: SetsStrings.fltTo.s, upperBound: true, date: $sets.filter.to)
                        }
                    }
                    row(SetsStrings.fltVersion.s) {
                        ChoicePills(options: facets.versions.map { .init(value: $0, title: $0) },
                                    selection: $sets.filter.versions, disabled: facets.disabledVersions,
                                    placeholder: SetsStrings.fltNone.s)
                    }
                    row(SetsStrings.fltKeyRoot.s) {
                        ChoicePills(options: facets.roots.map { .init(value: $0, title: Self.rootTitle($0)) },
                                    selection: $sets.filter.keyRoots, disabled: facets.disabledRoots,
                                    placeholder: SetsStrings.fltNone.s)
                    }
                    row(SetsStrings.fltScale.s) {
                        ChoicePills(options: facets.scales.map { .init(value: $0, title: Scales.scaleName($0)) },
                                    selection: $sets.filter.keyScales, disabled: facets.disabledScales,
                                    placeholder: SetsStrings.fltNone.s)
                    }
                    row(SetsStrings.fltTags.s) {
                        ChoicePills(options: facets.tags.map { .init(value: $0, title: $0) },
                                    selection: $sets.filter.tags, disabled: facets.disabledTags,
                                    placeholder: SetsStrings.fltNoTags.s)
                    }
                    row(SetsStrings.fltTracks.s) {
                        HStack(spacing: 10) {
                            CountFilterField(cue: SetsStrings.fltMin.s, value: $sets.filter.tracksMin)
                            CountFilterField(cue: SetsStrings.fltMax.s, value: $sets.filter.tracksMax)
                        }
                    }
                    row(SetsStrings.fltPluginCount.s) {
                        HStack(spacing: 10) {
                            CountFilterField(cue: SetsStrings.fltMin.s, value: $sets.filter.pluginsMin)
                            CountFilterField(cue: SetsStrings.fltMax.s, value: $sets.filter.pluginsMax)
                        }
                    }
                    pluginStateRow
                    row(SetsStrings.fltFiles.s) {
                        HStack(spacing: 8) {
                            FilterToggle(title: SetsStrings.fltComplete.s, isOn: $sets.filter.filesComplete,
                                         isEnabled: facets.canPickComplete || sets.filter.filesComplete)
                            FilterToggle(title: SetsStrings.fltMissingFiles.s, isOn: $sets.filter.filesMissing,
                                         isEnabled: facets.canPickMissingFiles || sets.filter.filesMissing)
                            FilterToggle(title: SetsStrings.unreadable.s, isOn: $sets.filter.filesUnreadable,
                                         isEnabled: facets.canPickUnreadable || sets.filter.filesUnreadable)
                        }
                    }
                    row(SetsStrings.fltRenders.s) {
                        HStack(spacing: 8) {
                            FilterToggle(title: SetsStrings.fltHasRenders.s, isOn: $sets.filter.previewHasRenders,
                                         isEnabled: facets.canPickHasRenders || sets.filter.previewHasRenders)
                            FilterToggle(title: SetsStrings.fltNoRenders.s, isOn: $sets.filter.previewNoRenders,
                                         isEnabled: facets.canPickNoRenders || sets.filter.previewNoRenders)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            footer
        }
        .onAppear(perform: refreshFacets)
        .onChange(of: app.sets.filter) { _, _ in refreshFacets() }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    // MARK: - Pieces

    /// "Some not installed" / "all installed": mutually exclusive, and disabled outright while the
    /// installed-plugin list is unknown.
    private var pluginStateRow: some View {
        @Bindable var sets = app.sets
        let known = app.sets.pluginsKnown
        return row(SetsStrings.fltPlugins.s) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    FilterToggle(title: SetsStrings.fltSomeMissing.s,
                                 isOn: Binding(get: { sets.filter.pluginsMissingOnly },
                                               set: { sets.filter.pluginsMissingOnly = $0
                                                      if $0 { sets.filter.pluginsAllInstalled = false } }),
                                 isEnabled: known && (facets.canPickMissingPlugins || sets.filter.pluginsMissingOnly))
                    FilterToggle(title: SetsStrings.fltAllInstalled.s,
                                 isOn: Binding(get: { sets.filter.pluginsAllInstalled },
                                               set: { sets.filter.pluginsAllInstalled = $0
                                                      if $0 { sets.filter.pluginsMissingOnly = false } }),
                                 isEnabled: known && (facets.canPickAllInstalled || sets.filter.pluginsAllInstalled))
                }
                if !known {
                    Text(SetsStrings.pluginStatusUnknown.s).font(Theme.fBadge).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(SetsStrings.fltMatches.f(facets.matches, app.catalog.sets.count))
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
            Spacer()
            PillButton(title: SetsStrings.fltReset.s) { app.sets.filter.clear() }
                .disabled(app.sets.filter.isEmpty)
            PillButton(title: CommonStrings.ok.s, kind: .primary) { dismiss() }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .frame(width: 130, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refreshFacets() {
        let meta = app.sets.meta
        facets = SetFilterFacets.make(sets: app.catalog.sets, filter: app.sets.filter, tagsOf: { meta.tagsOf($0) })
    }

    static func rootTitle(_ value: Int) -> String {
        switch value {
        case SetFilter.anyKey: return SetsStrings.fltAnyKey.s
        case SetFilter.noKey: return SetsStrings.fltNoKey.s
        default: return Scales.rootChoices.indices.contains(value) ? Scales.rootChoices[value] : ""
        }
    }
}
