// Port of src/HomeView.cs: the Home tab — Overview panel, then the Projects grid with a "New Live
// Set" tile first. Tiles are lazy and load their picture when they appear. Keeps the first-run screen.
import AliveCore
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
    static let maxColumns = 8

    /// upstream: `Math.Min(8, Math.Max(1, (Width + gap) / (target + gap)))`
    static func count(for width: CGFloat) -> Int {
        min(maxColumns, max(1, Int((width + gap) / (targetTileWidth + gap))))
    }
}

private struct HomeContent: View {
    @Environment(AppModel.self) private var app
    @FocusState private var gridFocused: Bool

    private static let gap = HomeContentColumns.gap

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                let columns = HomeContentColumns.count(for: proxy.size.width - Theme.pad * 2)
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            OverviewPanel()
                            projects(columns: columns)
                        }
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, 4)
                        .padding(.bottom, app.player.isStripVisible ? 96 : Theme.pad)
                    }
                    .focusable()
                    .focused($gridFocused)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .escape]) { press in
                        handle(press.key, columns: columns, scroller: scroller)
                    }
                }
            }
            if app.player.isStripVisible {
                NowPlayingStrip().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.selectAnimation, value: app.player.isStripVisible)
    }

    // MARK: - Projects

    private func projects(columns: Int) -> some View {
        let rows = app.home.rows
        return VStack(alignment: .leading, spacing: 16) {
            projectsHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: columns),
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
            isKeyboardFocused: gridFocused,
            isPinned: app.home.isPinned(path),
            isPlaying: app.player.isPlaying(setPath: path),
            onSelect: { app.selectedSetPath = path; gridFocused = true },
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

    private func handle(_ key: KeyEquivalent, columns: Int, scroller: ScrollViewProxy) -> KeyPress.Result {
        let rows = app.home.rows
        let current = app.selectedSetPath.flatMap { path in rows.firstIndex { $0.path == path } }
        switch key {
        case .return:
            guard let path = app.selectedSetPath else { return .ignored }
            app.openInLive(path: path)
        case .space:
            guard let path = app.selectedSetPath,
                  rows.first(where: { $0.path == path })?.hasRenders == true else { return .ignored }
            app.player.playRender(forSetAt: path)
        case .escape:
            guard app.selectedSetPath != nil else { return .ignored }
            app.selectedSetPath = nil
        default:
            guard let direction = Self.direction(of: key),
                  let next = TileNavigation.move(from: current, direction, columns: columns, count: rows.count)
            else { return .handled }
            let path = rows[next].path
            app.selectedSetPath = path
            withAnimation(Theme.selectAnimation) { scroller.scrollTo(path) }
        }
        return .handled
    }

    private static func direction(of key: KeyEquivalent) -> TileNavigation.Direction? {
        switch key {
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .upArrow: return .up
        case .downArrow: return .down
        default: return nil
        }
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
