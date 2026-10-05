// Mac-only: one row of the Samples list — a pill like the Sets rows, dimmed when nothing was ever
// taken from it, an outline when selected, a speaker while it plays. A sample row drags into Live.
import SwiftUI
import AliveCore

struct SampleRowView: View {
    let model: SamplesModel
    let row: SampleRow
    let layout: SampleColumnLayout
    let cells: SampleCells

    private static let indentStep: CGFloat = 20
    private static let chevronSlot: CGFloat = 14

    @State private var hovering = false

    var body: some View {
        let selected = model.selection == row.id
        let playing = isFile && model.isPlaying(row.id)
        let dim = cells.isDim(row) && !hovering && !selected
        HStack(spacing: 0) {
            ForEach(layout.columns, id: \.self) { c in
                cell(c, dim: dim, playing: playing)
            }
        }
        .padding(.horizontal, Theme.cellPadX)
        .frame(height: Theme.rowPillH)
        .background(selected ? Theme.tableSelection : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.text.opacity(selected ? 0.85 : 0), lineWidth: 1))
        .background(hovering && !selected ? Theme.rowHover : .clear, in: Capsule())
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .frame(height: Theme.rowH)
        .contentShape(Rectangle())
        .onTapGesture { model.click(row) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.activate(row) })
        .onDrag {
            guard let url = model.dragURL(for: row), let provider = NSItemProvider(contentsOf: url) else {
                return NSItemProvider()
            }
            return provider
        }
        .contextMenu { menu }
        .help(isFile ? SamplesStrings.dragHelp.s : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cells.text(.name, row))
        .accessibilityHint(isFile ? SamplesStrings.dragHelp.s : "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction {
            model.select(row.id)
            model.activate(row)
        }
        .accessibilityActions {
            if childCount != nil {
                Button(model.isOpen(row.id) ? SamplesStrings.collapse.s : SamplesStrings.expand.s) {
                    model.toggleFolder(row.id)
                }
            }
        }
    }

    private var isFile: Bool {
        if case .file = row.kind { return true }
        return false
    }

    // MARK: cells

    @ViewBuilder private func cell(_ c: SampleColumn, dim: Bool, playing: Bool) -> some View {
        let width = layout.width(c)
        Group {
            if c == .name {
                nameCell(dim: dim, playing: playing)
            } else {
                Text(cells.text(c, row))
                    .font(Theme.fBody)
                    .foregroundStyle(dim ? Theme.secondaryText : Theme.text)
                    .lineLimit(1)
                    .truncationMode(c.isPath ? .middle : .tail)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: c.isRightAligned ? .trailing : .leading)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: width)
        .frame(minWidth: width == nil ? 0 : nil, maxWidth: width == nil ? .infinity : nil)
    }

    private func nameCell(dim: Bool, playing: Bool) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: CGFloat(row.depth) * Self.indentStep, height: 1)
            if !model.isFlat { chevron }
            icon(playing: playing)
                .frame(width: 16)
            Text(cells.text(.name, row))
                .font(isFile ? Theme.fBody : Theme.fTitle)
                .foregroundStyle(dim ? Theme.secondaryText : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            tail
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder private func icon(playing: Bool) -> some View {
        if playing {
            IconView(icon: .volumeHigh, size: 12)
                .foregroundStyle(Theme.green)
                .symbolEffect(.variableColor.iterative, isActive: model.audio.isPlaying)
                .accessibilityLabel(SamplesStrings.playing.s)
        } else if isFile {
            IconView(icon: .wave, size: 11)
                .foregroundStyle(Theme.secondaryText)
                .opacity(canPlay ? 1 : 0.45)
        } else {
            IconView(icon: .folder, size: 12)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var canPlay: Bool {
        if case .file(let f) = row.kind { return model.index.files[f].canPreview }
        return false
    }

    /// How many things a folder holds; nil for a file, a flat list or an empty folder.
    private var childCount: Int? {
        guard case .folder(let d) = row.kind, !model.isFlat else { return nil }
        let folder = model.index.folders[d]
        let kids = folder.children.count + folder.files.count
        return kids > 0 ? kids : nil
    }

    /// The button that opens a folder: a chevron that turns down when it is open (tree only).
    /// The slot is kept on every row of the tree so the icons line up.
    @ViewBuilder private var chevron: some View {
        if childCount != nil {
            let open = model.isOpen(row.id)
            Button {
                model.toggleFolder(row.id)
            } label: {
                IconView(icon: .chevronDown, size: 10, weight: .bold)
                    .rotationEffect(.degrees(open ? 0 : -90))
                    .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
                    .frame(width: Self.chevronSlot, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? SamplesStrings.collapse.s : SamplesStrings.expand.s)
            .accessibilityLabel(open ? SamplesStrings.collapse.s : SamplesStrings.expand.s)
        } else {
            Color.clear.frame(width: Self.chevronSlot, height: 1)
        }
    }

    /// "53": what is inside a folder, as a plain count after its name.
    @ViewBuilder private var tail: some View {
        if let kids = childCount {
            Text(SampleFormat.number(kids))
                .font(Theme.fCaption)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .padding(.horizontal, 4)
                .help(SamplesStrings.folderItems.f(kids))
        }
    }

    // MARK: context menu

    @ViewBuilder private var menu: some View {
        if case .file(let f) = row.kind, model.index.files[f].canPreview {
            Button(model.isPlaying(row.id) ? SamplesStrings.stop.s : SamplesStrings.play.s) { model.toggle(file: f) }
        }
        if case .folder(let d) = row.kind, !model.isFlat,
           model.index.folders[d].children.count + model.index.folders[d].files.count > 0 {
            Button(model.isOpen(row.id) ? SamplesStrings.collapse.s : SamplesStrings.expand.s) { model.toggleFolder(row.id) }
        }
        if model.isFlat { Button(SamplesStrings.showInTree.s) { model.showInTree(row.id) } }
        Button(CommonStrings.showInFinder.s) { model.app.revealInFinder(path: row.id) }
        Button(SamplesStrings.copyPath.s) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.id, forType: .string)
        }
    }
}
