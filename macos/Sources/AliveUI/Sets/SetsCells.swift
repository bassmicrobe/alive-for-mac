// Mac-only: the cells of the sets table (upstream draws them in RowListView.cs).
// The cells take `app` as a plain parameter instead of @Environment(AppModel.self): when the row set
// shrinks (a root removed, a filter applied) NSTableView keeps cells alive outside the environment
// for a moment, and reading the environment there aborts with "No Observable object ... found".
import SwiftUI
import AliveCore

private enum CellStyle {
    /// Every cell is at least this tall, so the row pitch is the shared `Theme.rowH` rhythm of
    /// Plugins and Samples whatever a cell holds (the table adds its own row padding).
    static let height: CGFloat = Theme.rowH - 8
}

/// Text cell with the table's vertical rhythm. Metadata is `secondaryText` (AA on hover and
/// pressed fills); on the selected row's fill it turns to the full text colour.
struct SetTextCell: View {
    let text: String
    var right = false
    var dim = false
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(text)
            .font(Theme.fBody)
            .foregroundStyle(dim && prominence != .increased ? Theme.secondaryText : Theme.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: CellStyle.height, alignment: right ? .trailing : .leading)
    }
}

/// Star + name + "+N" badge + play button.
struct SetNameCell: View {
    let app: AppModel
    let set: SetEntry
    let isVersionRow: Bool

    var body: some View {
        HStack(spacing: 8) {
            PinStar(app: app, path: set.path)
            Text(SetFormat.displayName(set.name))
                .font(Theme.fTitle)
                .foregroundStyle(isVersionRow ? Theme.secondaryText : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(set.name)
            if set.collapsedCount > 0 {
                TagPill(text: SetsStrings.moreVersions.f(set.collapsedCount))
                    .help(SetsStrings.moreVersionsHelp.f(set.collapsedCount))
            }
            if !set.error.isEmpty {
                IconView(icon: .warning, size: 11)
                    .foregroundStyle(Theme.errorText)
                    .help(ReadErrorLog.note(set.error, of: set.path))
            }
            Spacer(minLength: 4)
            // What plays is always the render of the project's principal version, so a version
            // row gets no button (upstream: CanPlay = HasRenders && !childRow).
            if set.hasRenders, !isVersionRow {
                PlayGlyph(app: app, path: set.path)
            }
        }
        .frame(minHeight: CellStyle.height)
    }
}

/// The pin indicator; a click toggles the pin in home.cfg.
struct PinStar: View {
    let app: AppModel
    let path: String
    @State private var hovering = false

    var body: some View {
        let pinned = app.home.isPinned(path)
        Button {
            app.home.togglePin(path: path)
        } label: {
            IconView(icon: pinned ? .starFill : .star, size: 11)
                .foregroundStyle(pinned ? Theme.light : hovering ? Theme.text : Theme.secondaryText.opacity(0.5))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(pinned ? SetsStrings.unpinHelp.s : SetsStrings.pinHelp.s)
        .accessibilityLabel(pinned ? SetsStrings.unpinHelp.s : SetsStrings.pinHelp.s)
    }
}

private struct PlayGlyph: View {
    let app: AppModel
    let path: String
    @State private var hovering = false

    var body: some View {
        Button {
            app.sets.playRender(of: path)
        } label: {
            IconView(icon: .play, size: 9)
                .foregroundStyle(hovering ? Theme.onLight : Theme.secondaryText)
                .frame(width: 22, height: 22)
                .background(hovering ? Theme.light : Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(SetsStrings.playRenderHelp.s)
        .accessibilityLabel(SetsStrings.playRenderHelp.s)
    }
}

/// Coloured dot + number: green when all is there, red with the count of what is lost.
struct MissingMark: View {
    let total: Int
    let missing: Int
    var unreadable = false

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if unreadable {
                Text(SetsStrings.unreadable.s).foregroundStyle(Theme.errorText)
            } else if total > 0 || missing > 0 {
                if missing > 0 {
                    Text(String(missing)).foregroundStyle(Theme.errorText).monospacedDigit()
                }
                Circle().fill(missing > 0 ? Theme.red : Theme.green).frame(width: 7, height: 7)
            }
        }
        .font(Theme.fBody)
        .frame(minHeight: CellStyle.height)
    }
}

/// One aggregated mark per set for its plugins. When the installed-plugin list could not be read
/// nothing is known, so nothing is marked (no green dots either: they would promise a check that
/// did not happen).
struct PluginsMissedCell: View {
    let app: AppModel
    let set: SetEntry

    var body: some View {
        if app.sets.pluginsKnown {
            MissingMark(total: set.plugins.count, missing: set.missingPlugins)
        } else {
            Color.clear.frame(height: CellStyle.height)
        }
    }
}

/// Tags as pills; what does not fit collapses into "+n".
struct SetTagsCell: View {
    let app: AppModel
    let set: SetEntry

    var body: some View {
        _ = app.sets.metaRevision      // refresh when tags are edited
        let tags = app.sets.tags(of: set)
        return ViewThatFits(in: .horizontal) {
            pills(tags)
            if tags.count > 2 { pills(Array(tags.prefix(2)), more: tags.count - 2) }
            if tags.count > 1 { pills(Array(tags.prefix(1)), more: tags.count - 1) }
        }
        .frame(maxWidth: .infinity, minHeight: CellStyle.height, alignment: .leading)
        .clipped()
        .help(tags.joined(separator: ", "))
    }

    private func pills(_ tags: [String], more: Int = 0) -> some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { TagPill(text: $0) }
            if more > 0 { TagPill(text: SetsStrings.moreVersions.f(more)) }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
