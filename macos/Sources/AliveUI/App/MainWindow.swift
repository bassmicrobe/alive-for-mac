// Port of the toolbar/tab chrome in src/MainForm.cs: pill tabs, Filters, search, "N shown" and the
// round icon buttons. The title bar is hidden so the bar sits where upstream's custom chrome does.
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
        .frame(minWidth: 1120, minHeight: 600)
        .background(WindowTransparency(isTransparent: app.prefs.transparency))
        .sheet(item: $app.sheet) { sheet in SheetHost(sheet: sheet) }
        .preferredColorScheme(.dark)
        .task {
            AppDelegate.attach(app)
            app.start()
            await DebugLaunch.apply(to: app, openWindow: { openWindow(id: $0) },
                                    openSettings: { openSettings() })
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
        // Wide windows get a labelled "Folders" pill; when it does not fit (Japanese at the minimum
        // width, with the scan pill up) the same bar is used with the icon-only button.
        ViewThatFits(in: .horizontal) {
            bar(foldersLabelled: true)
            bar(foldersLabelled: false)
        }
        .animation(Theme.selectAnimation, value: app.catalog.isScanning)
        .padding(.leading, trafficLightInset)
        .padding(.trailing, Theme.pad)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func bar(foldersLabelled: Bool) -> some View {
        @Bindable var app = app
        return HStack(spacing: Theme.iconGap + 4) {
            PillTabs(items: MainTab.allCases.map { PillTabItem(value: $0, title: $0.title) },
                     selection: $app.tab)
                .fixedSize()
            PillButton(title: filtersTitle, icon: .filters) { app.presentFilters() }
                .disabled(!app.canPresentFilters)
                .fixedSize()
            SearchField()
            Text(app.shownLabel ?? CommonStrings.shownCount.f(app.shownCount))
                .font(Theme.fBody)
                .foregroundStyle(Theme.secondaryText)
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
                if foldersLabelled {
                    PillButton(title: CommonStrings.foldersLabel.s, icon: .folder) { app.presentScanFolders() }
                        .help(CommonStrings.scanFolders.s)
                        .fixedSize()
                } else {
                    CircleIconButton(icon: .folder, help: CommonStrings.scanFolders.s) { app.presentScanFolders() }
                }
                SettingsLink { IconView(icon: .settings) }
                    .buttonStyle(CircleIconButtonStyle())
                    .overlay(alignment: .topTrailing) { updateDot }
                    .help(CommonStrings.settings.s)
                    .accessibilityLabel(CommonStrings.settings.s)
                CircleIconButton(icon: .help, help: CommonStrings.help.s) { app.presentHelp() }
            }
        }
    }
}

extension TopBar {
    /// "Filters", or "Filters · 3" while filters are on.
    fileprivate var filtersTitle: String {
        let n = app.activeFilterCount
        return n > 0 ? "\(CommonStrings.filters.s) · \(n)" : CommonStrings.filters.s
    }

    /// A small dot on the gear while a newer release than the one already seen is out.
    @ViewBuilder fileprivate var updateDot: some View {
        if UpdateModel.shared.hasUnseenUpdate {
            Circle().fill(Theme.focus).frame(width: 8, height: 8)
                .offset(x: 1, y: -1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The sunken pill search field of the upstream toolbar. It takes focus only on a click or ⌘F:
/// not at launch, and it lets go while a sheet is up (the ring would show through behind it).
private struct SearchField: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 8) {
            IconView(icon: .magnifier, size: 12)
                .foregroundStyle(Theme.secondaryText)
            TextField("", text: $app.searchText,
                      prompt: Text(CommonStrings.searchIn.f(app.tab.title)).foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(Theme.fBody)
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .onExitCommand { app.searchText = ""; isFocused = false }
                .accessibilityLabel(CommonStrings.focusSearch.s)
            if !app.searchText.isEmpty {
                Button { app.searchText = "" } label: { IconView(icon: .close, size: 10) }
                    .buttonStyle(ClearFieldButtonStyle())
                    .help(CommonStrings.clearSearch.s)
                    .accessibilityLabel(CommonStrings.clearSearch.s)
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 80, idealWidth: 160, maxWidth: 320, minHeight: Theme.controlH, maxHeight: Theme.controlH)
        .background(Theme.sunken, in: Capsule())
        .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
        .onAppear { releaseInitialFocus() }
        .onChange(of: app.searchFocusRequest) { _, _ in isFocused = true }
        .onChange(of: app.sheet == nil) { _, noSheet in if !noSheet { isFocused = false } }
    }

    /// AppKit hands the first text field of a window the initial focus; give it back.
    private func releaseInitialFocus() {
        DispatchQueue.main.async {
            if app.searchFocusRequest == 0 { isFocused = false }
        }
    }
}

/// The "×" inside the search field: dim, brighter on hover, dips when pressed, focus ring.
private struct ClearFieldButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
            .frame(width: 18, height: 18)
            .contentShape(Circle())
            .focusRing(isFocused, cornerRadius: 9)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
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
                .foregroundStyle(Theme.secondaryText)
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
