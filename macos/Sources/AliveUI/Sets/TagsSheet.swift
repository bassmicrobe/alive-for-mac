// Port of src/NotesDialog.cs: one project's tags and note, keyed by the project folder (a project
// has a dozen versions next to each other and the tags belong to all of them).
import SwiftUI
import AliveCore

struct TagsSheet: View {
    let path: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var draft = ""
    @State private var note = ""
    @State private var loaded = false
    @FocusState private var noteFocused: Bool

    private var set: SetEntry? { app.sets.set(at: path) }

    var body: some View {
        SheetFrame(title: set?.name ?? (path as NSString).lastPathComponent, width: 560, height: 500) {
            VStack(alignment: .leading, spacing: 14) {
                if set == nil {
                    Text(SetsStrings.setGone.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(SetsStrings.tagsLabel.s)
                    TagInputField(tags: $tags, draft: $draft, cue: SetsStrings.tagCue.s)
                    suggestions
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(SetsStrings.noteLabel.s)
                    TextEditor(text: $note)
                        .scrollContentBackground(.hidden)
                        .font(Theme.fBody)
                        .foregroundStyle(Theme.text)
                        .focused($noteFocused)
                        .padding(8)
                        .frame(maxHeight: .infinity)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.cardR - 2, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            // TextEditor has no placeholder of its own; 13 pt = the editor's 8 pt
                            // padding plus the text container's 5 pt line inset.
                            if note.isEmpty {
                                Text(SetsStrings.notePlaceholder.s)
                                    .font(Theme.fBody)
                                    .foregroundStyle(Theme.secondaryText)
                                    .padding(.leading, 13).padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .focusRing(noteFocused, cornerRadius: Theme.cardR - 2)
                }
                HStack {
                    // Two lines, so the folder the tags apply to is not cut off; a leading space in a
                    // real folder name is dropped from the text only (the help keeps the full name).
                    let projectName = ((set?.projectDir ?? path) as NSString).lastPathComponent
                    Text(SetsStrings.appliesToProject.f(SetFormat.displayName(projectName)))
                        .font(Theme.fBadge).foregroundStyle(Theme.secondaryText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .help(SetsStrings.appliesToProject.f(projectName))
                    Spacer(minLength: 12)
                    PillButton(title: CommonStrings.cancel.s) { dismiss() }
                    PillButton(title: SetsStrings.save.s, kind: .primary, action: save)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .onAppear(perform: load)
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    /// The tags already used somewhere and not yet picked here: one click adds them.
    @ViewBuilder private var suggestions: some View {
        let _ = app.sets.metaRevision
        let rest = app.sets.meta.allTags().filter { tag in
            !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        if !rest.isEmpty {
            SetsFlowLayout(spacing: 6) {
                ForEach(rest, id: \.self) { tag in
                    SuggestionPill(text: tag) { tags = TagInput.merge(tag, into: tags) }
                }
            }
            .padding(.top, 2)
        }
    }

    private func load() {
        guard !loaded, let set else { return }
        loaded = true
        tags = app.sets.tags(of: set)
        note = app.sets.note(of: set)
    }

    private func save() {
        guard let set else { dismiss(); return }
        // A word typed and Save pressed at once: the tag has to be kept.
        let final = TagInput.commit(draft: draft, into: tags)
        app.sets.meta.set(set.projectDir, tags: final, note: note)
        dismiss()
    }
}

private struct SuggestionPill: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                IconView(icon: .plus, size: 8, weight: .bold)
                Text(text)
            }
            .font(Theme.fBadge)
            .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(hovering ? Theme.surfaceHover : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(SetsStrings.addTag.f(text))
    }
}
