// Port of PaintFolder / PaintSample (src/DetailPanel.cs): the panel for the selected folder or sample.
import SwiftUI
import AliveCore

struct SamplesPanel: View {
    let model: SamplesModel

    var body: some View {
        ScrollView {
            content
                .padding(Theme.panelPad + 2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        if let outside = model.outsideFolder {
            OutsidePanel(model: model, path: outside)
        } else {
            switch model.selectedKind {
            case .folder(let d)?: FolderPanel(model: model, folder: d)
            case .file(let f)?: SamplePanel(model: model, file: f)
            case nil: emptyPanel
            }
        }
    }

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SamplesStrings.panelNoSelection.s).font(Theme.fHead).foregroundStyle(Theme.text)
            Text(SamplesStrings.panelNoSelectionHint.s).font(Theme.fBody).foregroundStyle(Theme.textDim)
        }
    }
}

// MARK: - Folder

private struct FolderPanel: View {
    let model: SamplesModel
    let folder: Int

    var body: some View {
        let d = model.index.folders[folder]
        let use = model.usageUnknown ? nil : model.usage.of(folder: folder)
        // Worked out once per folder off the main actor, not on every evaluation of this body.
        let summary = use == nil ? nil : model.folderSummary(folder)
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: d.parent == nil ? rootTitle(d) : d.name, trailing: SampleFormat.megabytes(d.totalBytes))
            PathLink(model: model, path: d.path)
            VStack(spacing: 6) {
                PanelRow(label: SamplesStrings.panelSamples.s, value: SampleFormat.number(d.totalSamples))
                PanelRow(label: SamplesStrings.panelUsed.s,
                         value: use.map { SamplesStrings.panelUsedShare.f(SampleFormat.number($0.used), SampleFormat.share($0.used, of: d.totalSamples)) },
                         empty: SamplesStrings.noValue.s)
                PanelRow(label: SamplesStrings.panelProjects.s, value: use.map { SampleFormat.number($0.projects) },
                         empty: SamplesStrings.noValue.s)
                PanelRow(label: SamplesStrings.panelLastUsed.s, value: use.map { SampleFormat.day($0.lastUsed) },
                         empty: SamplesStrings.never.s)
                if let created = d.created { PanelRow(label: SamplesStrings.panelCreated.s, value: SampleFormat.day(created)) }
                copiesRow(d)
            }
            if let summary {
                UsageChart(months: summary.months)
                MostUsedList(model: model, files: summary.used, total: use?.used ?? 0)
                ProjectsList(model: model, sets: summary.projects)
            }
        }
    }

    /// A root's name is its whole path — as a heading it breaks in the middle of a word; the path
    /// stands in full right below it.
    private func rootTitle(_ d: SampleFolder) -> String {
        let last = (d.path as NSString).lastPathComponent
        return last.isEmpty ? d.name : last
    }

    @ViewBuilder private func copiesRow(_ d: SampleFolder) -> some View {
        let copies = model.copiesForPanel
        let n = copies.files(in: folder)
        if n > 0 {
            PanelRow(label: SamplesStrings.panelCopies.s,
                     value: SamplesStrings.panelCopiesValue.f(SampleFormat.number(n), SampleFormat.sampleSize(copies.bytes(in: folder))))
        }
    }
}

/// The ten most used samples: the whole list is the Most used lens.
private struct MostUsedList: View {
    let model: SamplesModel
    let files: [Int]
    let total: Int

    var body: some View {
        let top = Array(files.prefix(10))
        if !top.isEmpty {
            LinkList(heading: SamplesStrings.panelMostUsed.f(total), total: total, shown: top.count) {
                ForEach(top, id: \.self) { f in
                    LinkRow(text: model.index.files[f].name,
                            note: SampleFormat.number(model.usage.of(file: f)?.projects ?? 0)) {
                        model.showInTree(model.index.path(of: f))
                    }
                }
            }
        }
    }
}

// MARK: - Sample

private struct SamplePanel: View {
    let model: SamplesModel
    let file: Int

    var body: some View {
        let s = model.index.files[file]
        let path = model.index.path(of: file)
        let use = model.usageUnknown ? nil : model.usage.of(file: file)
        let others = model.copiesForPanel.others(of: file)
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: s.name, trailing: SampleFormat.sampleSize(s.size))
            WaveView(model: model, file: s, path: path)
            PathLink(model: model, path: path)
            VStack(spacing: 6) {
                if let info = model.info, info.path == path {
                    if info.durationMs > 0 { PanelRow(label: SamplesStrings.panelDuration.s, value: SampleFormat.duration(ms: info.durationMs)) }
                    if !info.format.isEmpty { PanelRow(label: SamplesStrings.panelFormat.s, value: info.format) }
                }
                PanelRow(label: SamplesStrings.panelProjects.s, value: use.map { SampleFormat.number($0.projects) },
                         empty: SamplesStrings.noValue.s)
                PanelRow(label: SamplesStrings.panelLastUsed.s, value: use.map { SampleFormat.day($0.lastUsed) },
                         empty: SamplesStrings.never.s)
                if let created = s.created { PanelRow(label: SamplesStrings.panelCreated.s, value: SampleFormat.day(created)) }
            }
            if let use {
                UsageChart(months: SampleMonths.count(use.sets))
            }
            if !others.isEmpty { copiesList(others) }
            if let use { ProjectsList(model: model, sets: SampleUsage.newest(use.sets)) }
        }
    }

    /// The same sound elsewhere in the library. Which copy the sets use says which one to keep; a
    /// click shows it in the tree.
    private func copiesList(_ others: [Int]) -> some View {
        LinkList(heading: SamplesStrings.panelCopiesList.f(others.count), total: others.count, shown: others.count) {
            ForEach(others, id: \.self) { c in
                LinkRow(text: model.index.location(of: model.index.files[c].folder),
                        // "used" says which copy the sets take; the path needs the rest of the row.
                        note: !model.usageUnknown && model.usage.of(file: c) != nil ? SamplesStrings.usedTag.s : "") {
                    model.showInTree(model.index.path(of: c))
                }
            }
        }
    }
}

// MARK: - Outside the library

private struct OutsidePanel: View {
    let model: SamplesModel
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: (path as NSString).lastPathComponent, trailing: "")
            PathLink(model: model, path: path)
            Text(SamplesStrings.outsideTitle.s).font(Theme.fTitle).foregroundStyle(Theme.text)
            Text(SamplesStrings.outsideBody.f((path as NSString).lastPathComponent))
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(title: SamplesStrings.addAsFolder.s, icon: .plus, kind: .primary) { model.addFolders([path]) }
        }
    }
}
