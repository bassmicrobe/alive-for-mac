// Port of the toolbar/tab chrome in src/MainForm.cs: pill tabs, Filters, search, "N shown" and the
// round icon buttons. The title bar is hidden so the bar sits where upstream's custom chrome does.
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            background
            VStack(spacing: 0) {
                TopBar()
                content
            }
            ToastOverlay(app: app)
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(WindowTransparency(isTransparent: app.prefs.transparency))
        .sheet(item: $app.sheet) { sheet in SheetHost(sheet: sheet) }
        .preferredColorScheme(.dark)
        .task {
            AppDelegate.attach(app)
            app.start()
        }
    }

    @ViewBuilder private var background: some View {
        if app.prefs.transparency {
            ZStack {
                VisualEffectBackground()
                Theme.bg.opacity(0.55)
            }
            .ignoresSafeArea()
        } else {
            Theme.bg.ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch app.tab {
        case .home: HomeView()
        case .sets: SetsView()
        case .plugins: PluginsView()
        case .samples: SamplesView()
        }
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    /// Room for the traffic lights, which overlay the hidden title bar.
    private let trafficLightInset: CGFloat = 70

    var body: some View {
        @Bindable var app = app
        HStack(spacing: Theme.iconGap + 4) {
            PillTabs(items: MainTab.allCases.map { PillTabItem(value: $0, title: $0.title) },
                     selection: $app.tab)
            PillButton(title: CommonStrings.filters.s, icon: .filters) { app.presentFilters() }
                .disabled(!app.canPresentFilters)
            SearchField()
            Text(CommonStrings.shownCount.f(app.shownCount))
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            if app.catalog.isScanning {
                ScanStatusPill(progress: app.catalog.progress)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Spacer(minLength: 8)
            HStack(spacing: Theme.iconGap) {
                CircleIconButton(icon: .stat, help: CommonStrings.tabStat.s) { openWindow(id: "stat") }
                CircleIconButton(icon: .folder, help: CommonStrings.scanFolders.s) { app.presentScanFolders() }
                SettingsLink { IconView(icon: .settings) }
                    .buttonStyle(CircleIconButtonStyle())
                    .help(CommonStrings.settings.s)
                CircleIconButton(icon: .help, help: CommonStrings.help.s) { app.presentHelp() }
            }
        }
        .animation(Theme.selectAnimation, value: app.catalog.isScanning)
        .padding(.leading, trafficLightInset)
        .padding(.trailing, Theme.pad)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

/// The sunken pill search field of the upstream toolbar.
private struct SearchField: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 8) {
            IconView(icon: .magnifier, size: 12)
                .foregroundStyle(Theme.textDim)
            TextField("", text: $app.searchText,
                      prompt: Text(CommonStrings.searchIn.f(app.tab.title)).foregroundStyle(Theme.textDim))
                .textFieldStyle(.plain)
                .font(Theme.fBody)
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .onExitCommand { app.searchText = ""; isFocused = false }
            if !app.searchText.isEmpty {
                Button { app.searchText = "" } label: { IconView(icon: .close, size: 10) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 200, maxWidth: 320, minHeight: Theme.controlH, maxHeight: Theme.controlH)
        .background(Theme.sunken, in: Capsule())
        .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
        .onChange(of: app.searchFocusRequest) { _, _ in isFocused = true }
        .accessibilityLabel(CommonStrings.focusSearch.s)
    }
}

/// "Scanning 120 / 754" with a small progress ring; indeterminate while the folder walk is still
/// counting. The current set's name is the tooltip.
private struct ScanStatusPill: View {
    let progress: CatalogProgress

    var body: some View {
        HStack(spacing: 8) {
            ProgressRing(fraction: progress.fraction)
                .frame(width: 13, height: 13)
            Text(label)
                .font(Theme.fSmall)
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.controlH - 6)
        .fixedSize()
        .background(Theme.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
        .help(progress.current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        progress.total > 0
            ? CommonStrings.scanProgress.f(progress.done, progress.total)
            : CommonStrings.scanning.s
    }
}

private struct ProgressRing: View {
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 2)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.light, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.hoverAnimation, value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.light, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
        }
    }
}
