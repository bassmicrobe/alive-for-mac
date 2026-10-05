// Port of src/CollectDialog.cs (the window; the logic is in ExportModel / core CollectAll).
import AppKit
import AliveCore
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    let path: String
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.export
        SheetFrame(title: model.set.name.isEmpty ? ExportStrings.title.s : ExportStrings.titleFor.f(model.set.name),
                   width: 640) {
            VStack(alignment: .leading, spacing: 14) {
                switch model.phase {
                case .idle, .counting: counting
                case .ready: choosing(model)
                case .running: running(model)
                case .done: done(model)
                }
            }
            .animation(Theme.hoverAnimation, value: model.phase)
        }
        .task(id: path) { await model.open(path: path) }
        // Closing the sheet stops a running copy; whatever it created is removed.
        .onDisappear { model.close() }
    }

    // MARK: states

    private var counting: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(ExportStrings.counting.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    @ViewBuilder
    private func choosing(_ model: ExportModel) -> some View {
        if let error = model.readError {
            Text(ReadErrorLog.note(error, of: path)).font(Theme.fBody).foregroundStyle(Theme.errorText)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            HStack { Spacer(); PillButton(title: ExportStrings.close.s) { app.sheet = nil } }
        } else {
            VStack(spacing: 2) {
                ForEach(model.groups.filter { $0.origin != .inProject }) { g in
                    OriginRow(group: g, isEnabled: model.canEditOptions) { model.setIncluded(g.origin, $0) }
                }
            }
            if let project = model.groups.first(where: { $0.origin == .inProject }) {
                ExtraLine(label: ExportText.label(.inProject), value: ExportText.groupNumbers(project))
            }
            if model.options.fromElsewhere, let line = ExportText.elsewhereFolders(model.elsewhereFolders) {
                Text(line).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                    .lineLimit(2).truncationMode(.middle)
                    .padding(.horizontal, 4)
                    .help(model.elsewhereFolders.joined(separator: "\n"))
            }
            if let line = ExportText.notFoundSummary(model.notFound.count) {
                DisclosureLine(summary: line, items: model.notFound.map { $0.name })
            }
            if let line = ExportText.refusedSummary(model.refused.count) {
                DisclosureLine(summary: line, items: model.refused.map { $0.name })
            }
            Divider().overlay(Theme.hairline)
            destinationRow(model)
            shelf(model)
        }
    }

    private func destinationRow(_ model: ExportModel) -> some View {
        HStack(spacing: 10) {
            Text(ExportStrings.destination.s).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            Text(model.outputPath)
                .font(Theme.fLabel)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(model.outputPath)
            Spacer(minLength: 8)
            QuietTextButton(title: ExportStrings.chooseDestination.s) { chooseDestination(model) }
        }
    }

    private func shelf(_ model: ExportModel) -> some View {
        let s = ExportText.summary(plan: model.plan, failure: model.failure, destinationExists: model.destinationExists,
                                   targetDir: model.targetDir, outputPath: model.outputPath)
        return HStack(spacing: 14) {
            Text(s.text)
                .font(Theme.fLabel)
                .foregroundStyle(s.isError ? Theme.errorText : Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                PillSwitch(label: ExportStrings.addToZip.s,
                           isOn: Binding(get: { model.options.toZip }, set: { model.setZip($0) }),
                           isEnabled: model.canEditOptions)
                Text(ExportStrings.addToZip.s).font(Theme.fBody).foregroundStyle(Theme.text)
                    .accessibilityHidden(true) // The switch already names this action.
            }
            PillButton(title: ExportStrings.cancel.s) { app.sheet = nil }
                .keyboardShortcut(.cancelAction)
            PillButton(title: ExportStrings.export.s, kind: .primary) { Task { await model.start() } }
                .disabled(!model.canExport)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func running(_ model: ExportModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ExportText.progress(model.progress)).font(Theme.fBody).foregroundStyle(Theme.text)
            ProgressBar(fraction: fraction(model.progress))
            Text(model.progress?.current ?? "")
                .font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
                .lineLimit(1).truncationMode(.middle)
                .frame(minHeight: 18, alignment: .leading)
            Divider().overlay(Theme.hairline)
            HStack {
                Spacer()
                PillButton(title: model.cancelling ? ExportStrings.cancelling.s : ExportStrings.cancel.s) { model.cancel() }
                    .disabled(model.cancelling)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minHeight: 150, alignment: .top)
    }

    private func fraction(_ p: CollectProgress?) -> Double? {
        guard let p, p.total > 0 else { return nil }
        switch p.phase {
        case .copying: return Double(p.done) / Double(p.total)
        case .writingSet, .packing: return 1
        }
    }

    @ViewBuilder
    private func done(_ model: ExportModel) -> some View {
        if let r = model.result {
            Text(ExportText.doneText(r))
                .font(Theme.fBody).foregroundStyle(r.failed.isEmpty ? Theme.green : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let line = ExportText.failedSummary(r.failed.count) {
                DisclosureLine(summary: line, items: r.failed.map { ExportStrings.listItem.f($0.name, $0.reason) })
            }
            Divider().overlay(Theme.hairline)
            HStack(spacing: 10) {
                Spacer()
                PillButton(title: ExportStrings.showInFinder.s, icon: .folder) { model.revealResult() }
                PillButton(title: ExportStrings.close.s, kind: .primary) { app.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: the save panel

    private func chooseDestination(_ model: ExportModel) {
        let panel = NSSavePanel()
        panel.message = ExportStrings.panelMessage.s
        panel.prompt = ExportStrings.panelPrompt.s
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = model.suggestedName
        panel.directoryURL = URL(fileURLWithPath: model.suggestedFolder, isDirectory: true)
        if model.options.toZip { panel.allowedContentTypes = [.zip] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setDestination(url.path)
    }
}

// MARK: - Rows

/// A switch, its label and how many files / bytes it brings. Dims when off.
private struct OriginRow: View {
    let group: CollectGroup
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            PillSwitch(label: ExportText.label(group.origin),
                       isOn: Binding(get: { group.included }, set: onChange), isEnabled: isEnabled)
            Text(ExportText.label(group.origin)).font(Theme.fBody).foregroundStyle(Theme.text)
                .accessibilityHidden(true) // Avoid repeating the switch's label in the combined row.
            Spacer(minLength: 8)
            Text(ExportText.groupNumbers(group))
                .font(Theme.fLabel)
                .monospacedDigit()
                .foregroundStyle(group.included ? Theme.text : Theme.secondaryText)
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .rowHover(cornerRadius: 10)
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { onChange(!group.included) } }
        .accessibilityElement(children: .combine)
    }
}

private struct ExtraLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).font(Theme.fLabel).monospacedDigit().foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
    }
}

/// ONE line about many files, with the list behind a disclosure (never one alert per file).
private struct DisclosureLine: View {
    let summary: String
    let items: [String]
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Theme.hoverAnimation) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    IconView(icon: .warning, size: 11).foregroundStyle(Theme.secondaryText)
                    Text(summary).font(Theme.fLabel)
                    Text(expanded ? ExportStrings.hideList.s : ExportStrings.showList.s)
                        .font(Theme.fLabel).foregroundStyle(Theme.secondaryText).underline()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(hovering ? Color.white : Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityValue(expanded ? CommonStrings.stateExpanded.s : CommonStrings.stateCollapsed.s)

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            Text(item).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 110)
                .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Switch and progress bar

/// The pill switch of the upstream dialog: a capsule track and a sliding light knob.
struct PillSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var isEnabled = true

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.surfacePressed : Theme.surface)
                Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1)
                Circle()
                    .fill(LinearGradient(colors: isOn ? [Theme.lightTop, Theme.light] : [Theme.textDim, Theme.textDim],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(3)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 42, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .brightness(hovering && isEnabled ? 0.08 : 0)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Theme.selectAnimation, value: isOn)
        .focusRing(focused && isEnabled, cornerRadius: 12)
        .onHover { hovering = $0 }
        .focused($focused)
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? CommonStrings.stateOn.s : CommonStrings.stateOff.s)
    }
}

/// A thin capsule bar; `nil` shows an indeterminate sweep.
private struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.19))
                Capsule().fill(Theme.text)
                    .frame(width: max(6, geo.size.width * CGFloat(fraction ?? 0.05)))
                    .animation(.linear(duration: 0.15), value: fraction)
            }
        }
        .frame(height: 6)
    }
}
