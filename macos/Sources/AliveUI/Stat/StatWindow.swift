// Port of nebula/NebulaForm.cs: the Stat window (`Window(id: "stat")`) — the whole library as a
// cloud of dots, a mapping panel on the left and the selected set on the right.
import SwiftUI
import AppKit

struct StatWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var folderSheet: AppSheet?

    private var model: StatModel { app.stat }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            HStack(alignment: .top, spacing: 16) {
                StatMappingPanel(model: model)
                    .frame(width: 300)
                cloudArea
                StatInspector(model: model, onShowInList: showInList)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(minWidth: 1040, idealWidth: 1320, minHeight: 640, idealHeight: 820)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .sheet(item: $folderSheet) { SheetHost(sheet: $0).environment(app) }
        .onAppear {
            model.syncCatalog(force: true)
        }
        .onChange(of: app.catalog.revision) { _, _ in model.syncCatalog() }
        .onChange(of: app.selectedSetPath) { _, _ in model.followMainSelection() }
        .onDisappear { model.saveNow() }
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
                CloudCanvas(model: model)
                CloudInputView(model: model, onKey: handle, onDoubleClick: { model.revealSelected() })
                if let hint { Text(hint).font(Theme.fBody).foregroundStyle(Theme.textDim).allowsHitTesting(false) }
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
        let hints = [StatStrings.hintRotate, .hintZoom, .hintPan, .hintOpen].map(\.s).joined(separator: "   ·   ")
        let progress = app.catalog.progress
        let lead = app.catalog.isScanning
            ? (progress.total > 0 ? CommonStrings.scanProgress.f(progress.done, progress.total) : CommonStrings.scanning.s)
            : StatStrings.projectsCount.f(model.visibleCount)
        return Text("\(lead)   ·   \(hints)")
            .font(Theme.fLabel)
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 20)
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
        .accessibilityValue(isOn ? "1" : "0")
    }
}
