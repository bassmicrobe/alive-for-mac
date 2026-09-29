// Port of the view half of src/PlayerDialog.cs: the player window (`Window(id: "player")`) with the
// waveform, transport, volume and the list of a set's renders.
import AliveCore
import SwiftUI

struct PlayerWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFile: String?

    private var player: PlayerModel { app.player }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if player.setPath == nil {
                EmptyState(icon: .wave, title: HomeStrings.playerEmptyTitle.s, message: HomeStrings.playerEmptyBody.s)
            } else {
                header
                WaveformView(waveform: player.waveform, progress: player.progress,
                             hint: waveHint, onSeek: { player.seek(toFraction: $0) })
                    .frame(height: 128)
                timeRow
                transport
                if player.hasFiles { fileList } else { Spacer(minLength: 0) }
                footer
            }
        }
        .padding(Theme.pad)
        .frame(minWidth: 480, minHeight: 540)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .background(spaceShortcut)
        // Nothing has been played yet: follow the selection, so the window opened from the menu
        // shows the set the person is looking at (paused, like upstream's "autoStart false").
        .task { await followSelectionIfIdle() }
        .onChange(of: app.selectedSetPath) { _, _ in Task { await followSelectionIfIdle() } }
    }

    private func followSelectionIfIdle() async {
        guard !player.hasPlayed, !player.isPlaying, let path = app.selectedSetPath,
              path.caseInsensitiveCompare(player.setPath ?? "") != .orderedSame else { return }
        await player.load(setAt: path, autoStart: false)
    }

    private var waveHint: String? {
        if let note = player.note { return note }
        if let wave = player.waveform, !wave.ok { return HomeStrings.waveFailed.s }
        return player.waveform == nil && player.hasFiles ? HomeStrings.waveReading.s : nil
    }

    /// Space plays and pauses while the window has focus.
    private var spaceShortcut: some View {
        Button("") { player.togglePlayPause() }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(player.setName).font(Theme.fHead).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 8)
            if let path = player.setPath {
                PillButton(title: HomeStrings.showSet.s, icon: .nextSet) { show(setAt: path) }
            }
        }
    }

    /// The link back to the set: select it in the main window's Sets tab and bring the window forward.
    private func show(setAt path: String) {
        app.searchText = ""
        app.tab = .sets
        app.selectedSetPath = path
        openWindow(id: "main")
    }

    private var timeRow: some View {
        HStack {
            Text(PlayerFormat.time(player.position))
            Spacer()
            Text(PlayerFormat.time(player.duration))
        }
        .font(Theme.fBody)
        .monospacedDigit()
        .foregroundStyle(Theme.secondaryText)
    }

    // MARK: - Transport

    private var transport: some View {
        ZStack {
            HStack(spacing: 10) {
                CircleIconButton(icon: .prevSet, help: HomeStrings.previousSet.s) { Task { _ = await player.stepSet(-1) } }
                CircleIconButton(icon: .prevTrack, help: HomeStrings.previousRender.s) { player.stepFile(-1) }
                    .disabled((player.currentIndex ?? 0) <= 0)
                BigPlayButton(isPlaying: player.isPlaying) { player.togglePlayPause() }
                    .disabled(player.currentFile == nil)
                CircleIconButton(icon: .nextTrack, help: HomeStrings.nextRender.s) { player.stepFile(+1) }
                    .disabled((player.currentIndex ?? 0) >= player.files.count - 1)
                CircleIconButton(icon: .nextSet, help: HomeStrings.nextSet.s) { Task { _ = await player.stepSet(+1) } }
            }
            HStack {
                Spacer()
                @Bindable var model = player
                VolumeControl(volume: $model.volume)
            }
        }
    }

    // MARK: - File list

    private var fileList: some View {
        let showFolder = player.files.contains { !$0.folder.isEmpty }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 26)
                Text(HomeStrings.colFile.s).frame(maxWidth: .infinity, alignment: .leading)
                if showFolder { Text(HomeStrings.colFolder.s).frame(width: 90, alignment: .leading) }
                Text(HomeStrings.colModified.s).frame(width: 90, alignment: .leading)
                Color.clear.frame(width: 24)
            }
            .font(Theme.fLabel)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, Theme.cellPadX)
            .padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(player.files.enumerated()), id: \.element.id) { index, file in
                        RenderRow(file: file, index: index, showFolder: showFolder,
                                  isCurrent: player.currentIndex == index,
                                  isPlaying: player.currentIndex == index && player.isPlaying,
                                  isSelected: selectedFile == file.id,
                                  onSelect: { selectedFile = file.id },
                                  onPlay: { play(index) },
                                  onPin: { Task { await player.togglePin(file) } },
                                  onReveal: { app.revealInFinder(path: file.path) })
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func play(_ index: Int) {
        if player.currentIndex == index, player.isCurrentOpen {
            player.togglePlayPause()
        } else {
            player.select(index, autoStart: true)
        }
    }

    // MARK: - Footer

    private var selected: RenderFile? {
        player.files.first { $0.id == selectedFile } ?? player.currentFile
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            PillButton(title: HomeStrings.showInFolder.s, icon: .folder) {
                if let file = selected { app.revealInFinder(path: file.path) }
            }
            .disabled(selected == nil)
            PillButton(title: (selected?.pinned ?? false) ? HomeStrings.clearPreview.s : HomeStrings.setAsPreview.s,
                       icon: (selected?.pinned ?? false) ? .starFill : .star) {
                if let file = selected { Task { await player.togglePin(file) } }
            }
            .disabled(selected == nil)
        }
    }
}

private struct BigPlayButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconView(icon: isPlaying ? .pause : .play, size: 20)
                .foregroundStyle(hovering ? Color.white : Theme.text)
                .frame(width: 58, height: 58)
                .background(hovering ? Theme.surfaceHover : Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .opacity(isEnabled ? 1 : 0.4)
        .help(isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playRender.s)
        .accessibilityLabel(isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playRender.s)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.hoverAnimation, value: configuration.isPressed)
    }
}

private struct RenderRow: View {
    let file: RenderFile
    let index: Int
    let showFolder: Bool
    let isCurrent: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onPin: () -> Void
    let onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                IconView(icon: isPlaying ? .pause : .play, size: 11)
                    .foregroundStyle(isCurrent ? Theme.text : Theme.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playFile.s)
            .accessibilityLabel(HomeStrings.playFile.s)
            // With the extension: "name.wav" and "name.mp3" of one render lie side by side.
            Text(file.name + "." + file.ext.lowercased())
                .font(Theme.fTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showFolder {
                Text(file.folder).font(Theme.fBody).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    .frame(width: 90, alignment: .leading)
            }
            Text(file.modified > .distantPast ? HomeModel.dateText(file.modified) : "")
                .font(Theme.fBody).foregroundStyle(Theme.secondaryText).monospacedDigit()
                .frame(width: 90, alignment: .leading)
            Button(action: onPin) {
                IconView(icon: file.pinned ? .starFill : .star, size: 12)
                    .foregroundStyle(file.pinned ? Theme.light : Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(file.pinned || hovering ? 1 : 0)
            .help(file.pinned ? HomeStrings.clearPreview.s : HomeStrings.setAsPreview.s)
            .accessibilityLabel(file.pinned ? HomeStrings.clearPreview.s : HomeStrings.setAsPreview.s)
        }
        .padding(.horizontal, Theme.cellPadX - 4)
        .frame(height: Theme.rowH - 4)
        .background(
            Capsule().fill(isSelected ? Theme.rowHover : Color.clear)
        )
        .overlay(Capsule().strokeBorder(isCurrent ? Theme.hairline.opacity(1.6) : .clear, lineWidth: 1.5))
        .rowHover()
        .onHover { hovering = $0 }
        .contentShape(Capsule())
        .onTapGesture(count: 2, perform: onPlay)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .contextMenu {
            Button(HomeStrings.playFile.s, action: onPlay)
            Button(file.pinned ? HomeStrings.clearPreview.s : HomeStrings.setAsPreview.s, action: onPin)
            Button(HomeStrings.showInFolder.s, action: onReveal)
        }
    }
}
