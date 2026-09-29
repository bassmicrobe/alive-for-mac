// Port of src/RootsDialog.cs: where to look for projects and for samples — a page each, edited as a
// draft and applied by "Scan". Folders come from the picker or from dropping them on the window;
// Live's own folders are one click away; each folder shows what it holds.
import SwiftUI
import AliveCore

struct RootsSheet: View {
    let kind: RootsKind
    @Environment(AppModel.self) private var app

    var body: some View {
        RootsEditor(kind: kind,
                    projects: .init(roots: app.settings.roots, disabled: app.settings.disabledRoots),
                    samples: .init(roots: app.settings.sampleRoots, disabled: app.settings.disabledSampleRoots))
    }
}

private struct RootsEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RootsDraft
    @State private var dropTargeted = false

    init(kind: RootsKind, projects: RootsDraft.Page, samples: RootsDraft.Page) {
        _draft = State(initialValue: RootsDraft(kind: kind, projects: projects, samples: samples))
    }

    var body: some View {
        SheetFrame(title: SetsStrings.rootsTitle.s, width: 620, height: 560) {
            VStack(alignment: .leading, spacing: 12) {
                PillTabs(items: [PillTabItem(value: RootsKind.projects, title: SetsStrings.rootsProjectsTab.s),
                                 PillTabItem(value: RootsKind.samples, title: SetsStrings.rootsSamplesTab.s)],
                         selection: $draft.kind)
                    .fixedSize()
                Text(hint).font(Theme.fSmall).foregroundStyle(Theme.textDim)
                list
                dropZone
                suggestions
                footer
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls.map(\.path))
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onDisappear { draft.cancelCounting() }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var hint: String {
        draft.kind == .projects ? SetsStrings.rootsHint.s : SetsStrings.rootsSamplesHint.s
    }

    // MARK: - List

    @ViewBuilder private var list: some View {
        let roots = draft.page.roots
        if roots.isEmpty {
            Text(draft.kind == .projects ? SetsStrings.rootsEmpty.s : SetsStrings.rootsSamplesEmpty.s)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(roots, id: \.self) { root in
                        RootRow(root: root, kind: draft.kind,
                                isOn: draft.page.isEnabled(root), isNested: draft.kind == .samples && draft.page.isNested(root),
                                count: draft.count(for: root),
                                toggle: { draft.page.set(root, enabled: $0) },
                                remove: { draft.page.remove(root) })
                            .onAppear { draft.ensureCount(root) }
                    }
                }
            }
        }
    }

    // MARK: - Adding

    private var dropZone: some View {
        Button(action: browse) {
            HStack(spacing: 8) {
                IconView(icon: .plus, size: 12)
                Text(dropTargeted ? SetsStrings.rootsDropRelease.s : SetsStrings.rootsDropHint.s)
            }
            .font(Theme.fSmall)
            .foregroundStyle(dropTargeted ? Theme.text : Theme.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(dropTargeted ? Theme.surfaceHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                    .strokeBorder(dropTargeted ? Theme.light : Theme.hairline,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.hoverAnimation, value: dropTargeted)
    }

    /// Projects: one-click folders found on this Mac. Samples: Live's own folders as a menu of ticks.
    @ViewBuilder private var suggestions: some View {
        if draft.kind == .projects {
            let found = RootSuggestions.make(env: app.catalog.env, existingRoots: draft.projects.roots)
            if !found.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(CommonStrings.suggestionsTitle.s)
                    SetsFlowLayout(spacing: 6) {
                        ForEach(found) { suggestion in
                            FilterToggle(title: suggestion.display(), isOn: Binding(
                                get: { false }, set: { _ in add([suggestion.path]) }))
                        }
                    }
                }
            }
        } else {
            let live = LiveFolderSuggestions.make(env: app.catalog.env, projectRoots: draft.projects.roots)
            if !live.isEmpty {
                HStack {
                    Menu {
                        ForEach(live) { item in
                            if item.startsGroup { Divider() }
                            Toggle(item.isProjects ? SetsStrings.rootsProjectsMark.f(item.title) : item.title,
                                   isOn: Binding(get: { draft.samples.index(of: item.path) != nil },
                                                 set: { toggleLive(item, on: $0) }))
                        }
                    } label: {
                        Text(SetsStrings.rootsFromLive.s)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    Spacer()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            PillButton(title: CommonStrings.cancel.s) { dismiss() }
            PillButton(title: SetsStrings.rootsScan.s, kind: .primary, action: apply)
                .disabled(!draft.canApply && draft.projectsChanged)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func browse() {
        let picked = FolderPicker.chooseFolders(message: CommonStrings.chooseFolderMessage.s,
                                                prompt: CommonStrings.chooseFolderPrompt.s)
        add(picked)
    }

    /// A file counts as its folder; a path that is not a folder is reported, not added.
    private func add(_ paths: [String]) {
        var failed = 0
        var page = draft.page
        for raw in paths {
            let folder = CatalogModel.folder(of: raw)
            guard RootSuggestions.directoryExists(folder) else { failed += 1; continue }
            page.add(folder)
        }
        draft.page = page
        if failed > 0 { app.toast(SetsStrings.rootsNotFolders.f(failed), kind: .error) }
    }

    private func toggleLive(_ item: LiveFolderSuggestion, on: Bool) {
        var page = draft.samples
        if on { page.add(item.path) } else { page.remove(page.roots.first { LiveFolderSuggestions.same($0, item.path) } ?? item.path) }
        draft.samples = page
    }

    /// One settings write and one rescan for any number of edits.
    private func apply() {
        if draft.projectsChanged {
            let page = draft.projects
            app.mutateSettings { $0.roots = page.roots; $0.disabledRoots = page.disabled }
            app.catalog.rescan()
        }
        if draft.samplesChanged {
            let page = draft.samples
            app.mutateSettings { $0.sampleRoots = page.roots; $0.disabledSampleRoots = page.disabled }
            app.samples.rescan()
        }
        dismiss()
    }
}

// MARK: - Row

private struct RootRow: View {
    let root: String
    let kind: RootsKind
    let isOn: Bool
    let isNested: Bool
    let count: Int?
    let toggle: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { toggle(!isOn) } label: {
                IconView(icon: isOn ? .check : .plus, size: 10, weight: .bold)
                    .opacity(isOn ? 1 : 0)
                    .foregroundStyle(Theme.onLight)
                    .frame(width: 18, height: 18)
                    .background(isOn ? AnyShapeStyle(Theme.light) : AnyShapeStyle(Theme.sunken), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: isOn ? 0 : 1))
            }
            .buttonStyle(.plain)
            .help(SetsStrings.rootOffHelp.s)
            .accessibilityLabel(SetsStrings.rootOffHelp.s)
            .accessibilityAddTraits(isOn ? .isSelected : [])

            Text(root)
                .font(Theme.fBody)
                .foregroundStyle(isOn ? Theme.text : Theme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root)
            Spacer(minLength: 8)
            countLabel
            CircleIconButton(icon: .close, help: SetsStrings.rootRemoveHelp.s, action: remove)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: Theme.rowPillH)
        .background(Theme.surface, in: Capsule())
    }

    @ViewBuilder private var countLabel: some View {
        if isNested && isOn {
            Text(SetsStrings.rootNested.s).font(Theme.fSmall).foregroundStyle(Theme.textDim)
        } else if let count {
            Text(count < 0 ? SetsStrings.rootNoAccess.s
                 : (kind == .projects ? SetsStrings.rootSetCount : SetsStrings.rootSampleCount).f(count))
                .font(Theme.fSmall)
                .foregroundStyle(count < 0 ? Theme.red : Theme.textDim)
                .monospacedDigit()
        } else {
            ProgressView().controlSize(.small).scaleEffect(0.7)
        }
    }
}
