// Mac-only: the menu bar extra's window (compact, dark, like the app). Works with the main
// window closed: every action goes through `AppModel` / `IntegrationCoordinator`.
import SwiftUI
import AppKit
import AliveCore

struct MenuBarContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = MenuBarSnapshot.make(sets: app.catalog.sets, pins: app.home.pinned,
                                            activity: app.catalog.history)
        VStack(alignment: .leading, spacing: 10) {
            activityLine(snapshot)
            if app.player.isStripVisible { nowPlaying }
            MenuBarProjects(snapshot: snapshot)
            Divider().overlay(Theme.hairline)
            footer
        }
        .padding(14)
        .frame(width: 330)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear { MainWindowPresenter.register { openWindow(id: "main") } }
    }

    // MARK: parts

    private func activityLine(_ snapshot: MenuBarSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(Theme.green).accessibilityHidden(true)
            if snapshot.savesToday > 0 {
                Text(IntegrationStrings.todaySaves.f(snapshot.savesToday))
            } else {
                Text(IntegrationStrings.noActivity.s).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 6)
            if snapshot.streak > 0 {
                Text(IntegrationStrings.streakDays.f(snapshot.streak)).foregroundStyle(Theme.secondaryText)
            }
        }
        .font(Theme.fBody).foregroundStyle(Theme.text)
        .lineLimit(1)
    }

    private var nowPlaying: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(IntegrationStrings.nowPlaying.s).font(Theme.fCaption).foregroundStyle(Theme.secondaryText)
                Text(app.player.currentFile?.name ?? app.player.setName)
                    .font(Theme.fBody).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            let playing = app.player.isPlaying
            iconButton(playing ? "pause.fill" : "play.fill",
                       label: playing ? IntegrationStrings.pause.s : IntegrationStrings.play.s) {
                app.player.togglePlayPause()
            }
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(IntegrationStrings.openAlive.s) { MainWindowPresenter.show() }
            Button(app.catalog.isScanning ? IntegrationStrings.scanning.s : IntegrationStrings.rescan.s) {
                app.catalog.rescan()
            }
            .disabled(app.catalog.isScanning)
            Spacer(minLength: 6)
            Button(IntegrationStrings.quit.s) { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Keep all projects reachable while the footer stays visible, even with many pins. Short lists
/// use their natural height; only a list taller than the available space needs to scroll.
struct MenuBarProjects: View {
    static let maxHeight: CGFloat = 360
    let snapshot: MenuBarSnapshot

    var body: some View {
        ViewThatFits(in: .vertical) {
            projects.fixedSize(horizontal: false, vertical: true)
            ScrollView { projects }
                .frame(height: Self.maxHeight)
        }
        .frame(maxHeight: Self.maxHeight)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !snapshot.pinned.isEmpty {
                section(IntegrationStrings.pinned.s, snapshot.pinned)
            }
            if snapshot.recent.isEmpty {
                Text(IntegrationStrings.noProjects.s).font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            } else {
                section(IntegrationStrings.recent.s, snapshot.recent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, _ sets: [SetEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title).padding(.bottom, 2)
            ForEach(sets) { set in MenuBarProjectRow(set: set) }
        }
    }
}

private struct MenuBarProjectRow: View {
    @Environment(AppModel.self) private var app
    let set: SetEntry

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(set.name).font(Theme.fBody).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                Text(set.modified.formatted(.relative(presentation: .named).locale(Localizer.shared.locale)))
                    .font(Theme.fCaption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 6)
            button("arrow.up.forward.app", IntegrationStrings.openInLive.s) { app.openInLive(path: set.path) }
            button("magnifyingglass", IntegrationStrings.showInAlive.s) { app.integration.showInAlive(path: set.path) }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .rowHover(cornerRadius: 8)
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryText)
        .help(label)
        .accessibilityLabel(label)
    }
}
