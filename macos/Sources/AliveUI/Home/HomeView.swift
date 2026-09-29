// Port of src/HomeView.cs: the Home tab — Overview panel, then the Projects grid with a "New Live
// Set" tile first. Tiles are lazy and load their picture when they appear. Keeps the first-run screen.
import AliveCore
import AppKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.catalog.hasEnabledRoots {
            HomeContent()
        } else {
            RootsEmptyState()
        }
    }
}

/// How many tiles fit a row.
enum HomeContentColumns {
    static let gap: CGFloat = 16
    static let targetTileWidth: CGFloat = 250

    /// upstream: `Math.Max(1, (Width + gap) / (target + gap))` (upstream also caps it at 8; the adaptive grid does not)
    static func count(for width: CGFloat) -> Int {
        max(1, Int((width + gap) / (targetTileWidth + gap)))
    }
}

private struct HomeContent: View {
    @Environment(AppModel.self) private var app
    /// True while the person is using the keyboard on the grid (the selection ring turns blue).
    @State private var keyboardActive = false
    @State private var keys = HomeKeyMonitor()

    private static let gap = HomeContentColumns.gap

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        OverviewPanel()
                        projects
                    }
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 4)
                    .padding(.bottom, app.player.isStripVisible ? 96 : Theme.pad)
                }
                // Not `.focusable()`, and no GeometryReader: both made AppKit's window structural-region
                // pass abort at start-up. Keys come from a local event monitor; the column count
                // is read from the window when a key arrives.
                .onChange(of: app.selectedSetPath) { _, path in
                    if let path { scroller.scrollTo(path) }
                }
                .onAppear { keys.start { key in handle(key) } }
                .onDisappear { keys.stop() }
            }
            if app.player.isStripVisible {
                NowPlayingStrip().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.selectAnimation, value: app.player.isStripVisible)
    }

    // MARK: - Projects

    private var projects: some View {
        let rows = app.home.rows
        return VStack(alignment: .leading, spacing: 16) {
            projectsHeader
            LazyVGrid(columns: [GridItem(.adaptive(minimum: HomeContentColumns.targetTileWidth), spacing: Self.gap)],
                      spacing: Self.gap) {
                newSetTile
                ForEach(rows) { set in tile(for: set) }
            }
            if rows.isEmpty, !app.catalog.sets.isEmpty {
                Text(HomeStrings.noMatches.s).font(Theme.fBody).foregroundStyle(Theme.textDim)
            }
        }
    }

    /// The same height as a project tile (picture 16:9 in an 8 pt frame, then the two text lines).
    private var newSetTile: some View {
        VStack(spacing: 0) {
            Color.clear.aspectRatio(ThumbnailPipeline.aspect, contentMode: .fit).padding(8)
            Color.clear.frame(height: 50)
        }
        .overlay { NewSetTile { app.launchLive() } }
    }

    private var projectsHeader: some View {
        HStack(spacing: 10) {
            Text(HomeStrings.projects.s).font(Theme.fHead).foregroundStyle(Theme.text)
            PinnedFirstToggle(isOn: app.home.pinnedFirst) { app.home.togglePinnedFirst() }
            if app.catalog.sets.isEmpty, app.catalog.isReady {
                Text(HomeStrings.nothingIndexed.s).font(Theme.fLabel).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func tile(for set: SetEntry) -> some View {
        let path = set.path
        return ProjectTile(
            set: set,
            isSelected: app.selectedSetPath == path,
            isKeyboardFocused: keyboardActive,
            isPinned: app.home.isPinned(path),
            isPlaying: app.player.isPlaying(setPath: path),
            onSelect: { app.selectedSetPath = path; keyboardActive = false },
            onOpen: { app.openInLive(path: path) },
            onPlay: { app.selectedSetPath = path; app.player.playRender(forSetAt: path) },
            onTogglePin: { app.togglePin(path: path) }
        )
        .id(path)
        .contextMenu { menu(for: set) }
    }

    @ViewBuilder private func menu(for set: SetEntry) -> some View {
        let path = set.path
        Button(CommonStrings.openInLive.s) { app.openInLive(path: path) }
        if set.hasRenders {
            Button(app.player.isPlaying(setPath: path) ? HomeStrings.pauseRender.s : HomeStrings.playRender.s) {
                app.selectedSetPath = path
                app.player.playRender(forSetAt: path)
            }
            OpenPlayerButton(path: path)
        }
        Button(app.home.isPinned(path) ? HomeStrings.unpin.s : HomeStrings.pinProject.s) { app.togglePin(path: path) }
        Divider()
        Button(CommonStrings.arrangementPreview.s) { app.sheet = .preview(path: path) }
        Button(CommonStrings.tagsAndNotes.s) { app.sheet = .tags(path: path) }
        Button(HomeStrings.showDetails.s) {
            app.selectedSetPath = path
            app.tab = .sets
        }
        Button(CommonStrings.rescue.s) { app.sheet = .rescue(path: path) }
        Divider()
        Button(CommonStrings.showInFinder.s) { app.revealInFinder(path: path) }
    }

    // MARK: - Keyboard

    /// Returns true when the key was ours.
    private func handle(_ key: HomeKeyMonitor.Key) -> Bool {
        let columns = HomeContentColumns.count(for: (NSApp.keyWindow?.contentView?.bounds.width ?? 1200) - Theme.pad * 2)
        guard app.sheet == nil, app.tab == .home else { return false }
        let rows = app.home.rows
        let current = app.selectedSetPath.flatMap { path in rows.firstIndex { $0.path == path } }
        switch key {
        case .return:
            guard let path = app.selectedSetPath else { return false }
            app.openInLive(path: path)
        case .space:
            guard let path = app.selectedSetPath,
                  rows.first(where: { $0.path == path })?.hasRenders == true else { return false }
            app.player.playRender(forSetAt: path)
        case .move(let direction):
            keyboardActive = true
            guard let next = TileNavigation.move(from: current, direction, columns: columns, count: rows.count) else { return true }
            app.selectedSetPath = rows[next].path
        }
        return true
    }
}

/// "Open player" needs the window environment, which a plain menu builder does not have.
private struct OpenPlayerButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let path: String

    var body: some View {
        Button(HomeStrings.openPlayer.s) {
            openWindow(id: "player")
            Task { await app.player.load(setAt: path, autoStart: false) }
        }
    }
}

/// The star next to "Projects": pinned projects first, or by date only.
private struct PinnedFirstToggle: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(icon: isOn ? .starFill : .star, size: 13)
                .foregroundStyle(isOn ? Theme.light : hovering ? Theme.text : Theme.textDim)
                .frame(width: 26, height: 26)
                .background(hovering ? Theme.surface : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(isOn ? HomeStrings.pinnedFirstOn.s : HomeStrings.pinnedFirstOff.s)
        .accessibilityLabel(isOn ? HomeStrings.pinnedFirstOn.s : HomeStrings.pinnedFirstOff.s)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
