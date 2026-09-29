// Port of the tile painting in src/HomeView.cs (picture, name, "date · place", star, play button)
// as SwiftUI views, plus the "New Live Set" tile and the compact now-playing strip.
import AliveCore
import SwiftUI

struct ProjectTile: View {
    let set: SetEntry
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let isPinned: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false

    private static let corner = Theme.cardR

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArrangementThumbnailView(path: set.path)
                .overlay(alignment: .topTrailing) { starButton.padding(6) }
                .overlay(alignment: .bottomTrailing) {
                    if set.hasRenders { PlayBadge(isPlaying: isPlaying, action: onPlay).padding(8) }
                }
                .padding(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(HomeModel.subtitle(for: set))
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(fill, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .onTapGesture(count: 2, perform: onOpen)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(set.name)
        .accessibilityHint(HomeModel.subtitle(for: set))
        .accessibilityAction(named: CommonStrings.openInLive.s, onOpen)
    }

    /// Hover and selection are told apart: hover lifts the surface, selection draws the ring.
    private var fill: Color {
        isSelected ? Theme.surfaceHover : hovering ? Theme.surfaceHover.opacity(0.7) : Theme.surface
    }

    private var border: Color {
        if isSelected { return isKeyboardFocused ? Theme.focus : Theme.light.opacity(0.85) }
        return hovering ? Color.white.opacity(0.10) : Theme.cardBorder
    }

    private var starButton: some View {
        Button(action: onTogglePin) {
            IconView(icon: isPinned ? .starFill : .star, size: 13)
                .foregroundStyle(isPinned ? Theme.lightTop : Theme.text)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(isPinned || hovering ? 0.45 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isPinned || hovering || isSelected ? 1 : 0)
        .help(isPinned ? HomeStrings.unpin.s : HomeStrings.pinProject.s)
        .accessibilityLabel(isPinned ? HomeStrings.unpin.s : HomeStrings.pinProject.s)
    }
}

/// The round play button on a tile's picture; pulses while that render is playing.
private struct PlayBadge: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isPlaying {
                    Circle().stroke(Theme.light.opacity(0.6), lineWidth: 2)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                IconView(icon: isPlaying ? .pause : .play, size: 12)
                    .foregroundStyle(hovering ? Theme.onLight : Theme.lightTop)
                    .frame(width: 34, height: 34)
                    .background(hovering ? Theme.light : Color.black.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .frame(width: 34, height: 34)
            .scaleEffect(hovering ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .onChange(of: isPlaying, initial: true) { _, playing in
            pulse = false
            guard playing else { return }
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
        .help(isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playRender.s)
        .accessibilityLabel(isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playRender.s)
    }
}

/// The first tile: starting a set from here is closer at hand than finding one already started.
struct NewSetTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                IconView(icon: .plus, size: 15, weight: .semibold)
                    .foregroundStyle(hovering ? Theme.onLight : Theme.textDim)
                    .frame(width: 34, height: 34)
                    .background(hovering ? Theme.light : Theme.surface, in: Circle())
                Text(HomeStrings.newLiveSet.s)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.text : Theme.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hovering ? Theme.surface.opacity(0.6) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                    .strokeBorder(hovering ? Theme.textDim : Theme.hairline,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .help(HomeStrings.newLiveSetHelp.s)
    }
}

/// A compact player at the bottom of Home: what plays, a scrub bar and the way to the window.
struct NowPlayingStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let player = app.player
        HStack(spacing: 12) {
            Button { player.togglePlayPause() } label: {
                IconView(icon: player.isPlaying ? .pause : .play, size: 13)
                    .foregroundStyle(Theme.onLight)
                    .frame(width: 32, height: 32)
                    .background(Theme.light, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? HomeStrings.pauseRender.s : HomeStrings.playRender.s)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentFile?.name ?? "").font(Theme.fTitle).foregroundStyle(Theme.text).lineLimit(1)
                Text(player.setName).font(Theme.fSmall).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            .frame(width: 180, alignment: .leading)
            Text(PlayerFormat.time(player.position)).monospacedDigit()
            ScrubBar(value: player.progress, label: HomeStrings.nowPlayingSeek.s) { player.seek(toFraction: $0) }
            Text(PlayerFormat.time(player.duration)).monospacedDigit()
            CircleIconButton(icon: .wave, help: HomeStrings.openPlayer.s) { openWindow(id: "player") }
            CircleIconButton(icon: .close, help: HomeStrings.stopPlayback.s) { player.unload() }
        }
        .font(Theme.fSmall)
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 16)
    }
}
