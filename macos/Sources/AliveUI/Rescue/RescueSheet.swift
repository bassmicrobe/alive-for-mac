// Port of src/RescueDialog.cs (the window; the logic is in RescueModel / core RescueSession).
import AliveCore
import SwiftUI

struct RescueSheet: View {
    let path: String
    @Environment(AppModel.self) private var app

    private static let rowHeight: CGFloat = 36
    private static let maxRows = 10

    var body: some View {
        let model = app.rescue
        SheetFrame(title: title(model), width: 660) {
            VStack(alignment: .leading, spacing: 12) {
                if model.phase == .loading || model.phase == .idle {
                    loading
                } else {
                    paragraph(model)
                    refused(model)
                    if model.usable { checklist(model) }
                    hint(model)
                    buttons(model)
                }
            }
            .animation(Theme.hoverAnimation, value: model.phase)
        }
        .task(id: path) { await model.open(path: path) }
        // Always clear the probe up: it is an .als inside a project folder, and left there for
        // good it would one day be opened instead of the real set.
        .onDisappear { model.close() }
    }

    private func title(_ model: RescueModel) -> String {
        model.setName.isEmpty
            ? RescueStrings.title.s
            : RescueStrings.titleFor.f(model.setName)
    }

    // MARK: pieces

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(RescueStrings.loading.s).font(Theme.fBody).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func paragraph(_ model: RescueModel) -> some View {
        let text: String
        if let s = model.session {
            text = model.status.map(RescueText.status) ?? RescueText.header(s)
        } else {
            text = ""
        }
        let isVerdict = model.session?.isFinished == true && model.status == nil
        return Text(text)
            .font(Theme.fBody)
            .foregroundStyle(isVerdict ? Theme.green : Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            .textSelection(.enabled)
            .id(model.revision)
    }

    /// The plugins Live refused in the logged attempt: ONE line, the list behind a disclosure.
    @ViewBuilder
    private func refused(_ model: RescueModel) -> some View {
        if let groups = model.session?.history?.failureGroups,
           let summary = RescueText.refusedSummary(groups) {
            RefusedSummary(summary: summary, groups: groups)
        }
    }

    private func checklist(_ model: RescueModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(listLabel(model)).font(Theme.fLabel).foregroundStyle(Theme.textDim)
                Spacer(minLength: 8)
                if model.canEditList {
                    QuietTextButton(title: RescueStrings.allOff.s) { model.setAll(enabled: false) }
                    QuietTextButton(title: RescueStrings.allOn.s) { model.setAll(enabled: true) }
                    QuietTextButton(title: RescueStrings.suggested.s) { model.applySuggestion() }
                }
            }
            let rows = min(model.targets.count, Self.maxRows)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.targets) { slot in
                        PluginCheckRow(slot: slot, isOn: model.checked.contains(slot.uid),
                                       note: model.notes[slot.uid], isEnabled: model.canEditList) {
                            model.toggle(slot)
                        }
                        .frame(height: Self.rowHeight)
                    }
                }
            }
            .scrollIndicators(model.targets.count > Self.maxRows ? .visible : .hidden)
            .frame(height: CGFloat(max(rows, 3)) * Self.rowHeight, alignment: .top)
        }
    }

    private func listLabel(_ model: RescueModel) -> String {
        var label = RescueStrings.listLabel.f(model.targets.count)
        if let n = model.session?.unaddressable, n > 0 {
            label += "  ·  " + RescueStrings.listUnidentified.f(n)
        }
        return label
    }

    private func hint(_ model: RescueModel) -> some View {
        Text(RescueText.hint(usable: model.usable, waiting: model.isWaiting || model.phase == .preparing,
                             liveRunning: model.liveRunning, disabledCount: model.disabled.count,
                             probeFileName: model.probeFileName))
            .font(Theme.fSmall)
            .foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
    }

    private func buttons(_ model: RescueModel) -> some View {
        HStack(spacing: 10) {
            Spacer()
            if model.isWaiting {
                PillButton(title: RescueStrings.didNotOpen.s) { model.answer(opened: false) }
                PillButton(title: RescueStrings.didOpen.s) { model.answer(opened: true) }
            }
            if model.canSaveRescued {
                PillButton(title: RescueStrings.saveRescued.s, icon: .check) {
                    Task { await model.saveRescued() }
                }
            }
            PillButton(title: runTitle(model), kind: .primary) { run(model) }
                .disabled(!model.runEnabled)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func runTitle(_ model: RescueModel) -> String {
        switch model.runTitle {
        case .close: return RescueStrings.close.s
        case .open: return RescueStrings.openProbe.s
        case .next: return RescueStrings.nextProbe.s
        case .again: return RescueStrings.probeAgain.s
        case .waiting: return RescueStrings.waiting.s
        }
    }

    private func run(_ model: RescueModel) {
        if !model.usable { app.sheet = nil; return }
        Task { await model.runProbe() }
    }
}

// MARK: - Refused plugins (one line + disclosure)

private struct RefusedSummary: View {
    let summary: String
    let groups: [PluginFailureGroup]
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Theme.hoverAnimation) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    IconView(icon: .warning, size: 12).foregroundStyle(Theme.textDim)
                    Text(summary).font(Theme.fLabel)
                    Text(expanded ? RescueStrings.refusedHide.s : RescueStrings.refusedShow.s)
                        .font(Theme.fLabel).foregroundStyle(Theme.textDim).underline()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(hovering ? Color.white : Theme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityValue(expanded ? "expanded" : "collapsed")

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { g in
                        Text(RescueText.refusedLine(g)).font(Theme.fSmall).foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Quick text buttons ("All Off", "All On", "Suggested")

struct QuietTextButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.fLabel)
                .foregroundStyle(hovering ? Color.white : Theme.textDim)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(hovering ? Theme.rowHover : .clear, in: Capsule())
        }
        .buttonStyle(QuietPressStyle())
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct QuietPressStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .focusRing(isFocused, cornerRadius: 13)
    }
}
