// Port of nebula/NebulaForm.cs: the Stat window (`Window(id: "stat")`) — the whole library as a
// cloud of dots, a mapping panel on the left and the selected set on the right.
import SwiftUI
import AppKit

struct StatWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var activeState
    @State private var folderSheet: AppSheet?

    private var model: StatModel { app.stat }

    var body: some View {
        // Grows with the interface scale like the main window (9ce4b4b), never past the screen.
        let size = StatWindowSize.make(uiScale: app.settings.uiScale,
                                       screen: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size)
        return VStack(alignment: .leading, spacing: 14) {
            toolbar
            HStack(alignment: .top, spacing: 16) {
                StatMappingPanel(model: model)
                    .frame(width: Theme.panelW)
                cloudArea
                StatInspector(model: model, onShowInList: showInList)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(minWidth: size.minimum.width, idealWidth: size.ideal.width,
               minHeight: size.minimum.height, idealHeight: size.ideal.height)
        .background(Theme.bg)
        .background(WindowSizer(size: size.ideal))
        .preferredColorScheme(.dark)
        .sheet(item: $folderSheet) { SheetHost(sheet: $0).environment(app) }
        .onAppear {
            model.syncCatalog(force: true)
            model.isKeyWindow = activeState == .key
        }
        // The cloud shows the main window's catalog: it follows each rescan of it by revision.
        .onChange(of: app.catalog.revision) { _, _ in model.syncCatalog() }
        .onChange(of: app.selectedSetPath) { _, _ in model.followMainSelection() }
        .onChange(of: activeState) { _, state in model.isKeyWindow = state == .key }
        .onDisappear {
            model.isKeyWindow = false
            model.saveNow()
        }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            SpinToggle(isOn: model.config.spin) { model.setSpin($0) }
            PillButton(title: StatStrings.resetView.s) { model.resetView() }
            StatCameraBar { model.setPreset($0) }
            Spacer(minLength: 8)
            CircleIconButton(icon: .folder, help: CommonStrings.scanFolders.s) {
                folderSheet = .roots(.projects)
            }
        }
    }

    // MARK: cloud

    private var cloudArea: some View {
        VStack(spacing: 6) {
            ZStack {
                // The picture is drawn for the eyes; the input view over it is what VoiceOver reads.
                CloudCanvas(model: model)
                    .accessibilityHidden(true)
                CloudInputView(model: model, onKey: handle, onDoubleClick: { model.revealSelected() })
                if let hint { Text(hint).font(Theme.fBody).foregroundStyle(Theme.secondaryText).allowsHitTesting(false) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
            statusLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String? {
        guard app.catalog.isLoaded, model.visibleCount == 0, !app.catalog.isScanning else { return nil }
        return app.catalog.hasEnabledRoots ? StatStrings.hintNothing.s : StatStrings.hintNoFolders.s
    }

    private var statusLine: some View {
        let hintList = [StatStrings.hintRotate, .hintZoom, .hintPan, .hintOpen].map(\.s)
        let progress = app.catalog.progress
        let lead = app.catalog.isScanning
            ? (progress.total > 0 ? CommonStrings.scanProgress.f(progress.done, progress.total) : CommonStrings.scanning.s)
            : StatStrings.projects(model.visibleCount)
        // The hints are dropped from the end as the width shrinks (Japanese is longer), never cut
        // mid-word; the full line is the tooltip.
        let line: (Int) -> String = { count in
            ([lead] + hintList.prefix(count)).joined(separator: "   ·   ")
        }
        return ViewThatFits(in: .horizontal) {
            ForEach((0...hintList.count).reversed(), id: \.self) { count in
                Text(line(count)).lineLimit(1).fixedSize()
            }
        }
        .font(Theme.fLabel)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 20)
        .help(line(hintList.count))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line(hintList.count))
    }

    // MARK: actions

    private func handle(_ key: CloudKey) {
        switch key {
        case .toggleSpin: model.toggleSpin()
        case .reset: model.resetView()
        case .openInLive: model.openSelectedInLive()
        case .deselect: model.deselect()
        }
    }

    /// "Show in list": the Sets tab with this set selected, and the main window brought forward.
    private func showInList() {
        guard model.showSelectedInList() else { return }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The "Spin" pill of the toolbar: lit while the cloud turns by itself.
private struct SpinToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button { onChange(!isOn) } label: {
            HStack(spacing: 6) {
                IconView(icon: .refresh, size: 11)
                Text(StatStrings.spin.s)
            }
        }
        .buttonStyle(PillButtonStyle(kind: isOn ? .primary : .quiet))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? CommonStrings.stateOn.s : CommonStrings.stateOff.s)
    }
}

/// Gives the window a comfortable first size: a `Window` scene opens at the content's minimum, which
/// leaves the cloud a narrow strip between the panels (upstream opens at 1360 × 860). Once, and never
/// larger than the screen.
private struct WindowSizer: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, !context.coordinator.done else { return }
            context.coordinator.done = true
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let target = CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
            window.setContentSize(target)
            window.center()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var done = false }
}
