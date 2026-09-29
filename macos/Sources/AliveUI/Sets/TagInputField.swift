// Port of src/TagEditor.cs: the tags already set lie as pills, the caret stands right after the
// last one, and a new tag is typed here and closed with a comma or Return. Values are invented,
// not picked from a ready list.
import SwiftUI
import AliveCore

/// The pure part: what typing does to the tag list.
enum TagInput {
    /// A comma closes a tag: everything before the last comma goes into pills, the tail stays typed.
    static func absorb(draft: String, into tags: [String]) -> (tags: [String], draft: String) {
        guard let comma = draft.lastIndex(of: ",") else { return (tags, draft) }
        let closed = String(draft[..<comma])
        let rest = String(draft[draft.index(after: comma)...])
        return (merge(closed, into: tags), rest.trimmingCharacters(in: .whitespaces).isEmpty ? "" : rest)
    }

    /// A word typed and not yet closed still counts (Save pressed straight away).
    static func commit(draft: String, into tags: [String]) -> [String] {
        merge(draft, into: tags)
    }

    /// Adds the comma-separated tags of `text` to `tags`: trimmed, no repeats (case-insensitive),
    /// the existing order kept (same rules as `ProjectMeta.parseTags`).
    static func merge(_ text: String, into tags: [String]) -> [String] {
        var result = tags
        for tag in ProjectMeta.parseTags(text) where !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            result.append(tag)
        }
        return result
    }
}

struct TagInputField: View {
    @Binding var tags: [String]
    @Binding var draft: String
    let cue: String
    @FocusState private var focused: Bool

    var body: some View {
        SetsFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                RemovableTag(text: tag) { tags.removeAll { $0 == tag } }
            }
            TextField("", text: $draft, prompt: Text(tags.isEmpty ? cue : "").foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(Theme.fBody)
                .foregroundStyle(Theme.text)
                .focused($focused)
                .frame(minWidth: 140, idealWidth: 200)
                .frame(height: 24)
                .onSubmit(commit)
                .onKeyPress(.delete) {
                    // Backspace in an empty field takes the last pill back.
                    guard draft.isEmpty, !tags.isEmpty else { return .ignored }
                    tags.removeLast()
                    return .handled
                }
                .onChange(of: draft) { _, new in
                    let result = TagInput.absorb(draft: new, into: tags)
                    if result.tags != tags { tags = result.tags }
                    if result.draft != new { draft = result.draft }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.cardR - 2, style: .continuous))
        .focusRing(focused, cornerRadius: Theme.cardR - 2)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }

    private func commit() {
        tags = TagInput.commit(draft: draft, into: tags)
        draft = ""
    }
}

private struct RemovableTag: View {
    let text: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text).font(Theme.fBadge).foregroundStyle(Theme.text)
            Button(action: remove) {
                IconView(icon: .close, size: 8, weight: .bold)
                    .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(SetsStrings.removeTag.f(text))
            .accessibilityLabel(SetsStrings.removeTag.f(text))
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: 22)
        .background(Color.white.opacity(hovering ? 0.16 : 0.10), in: Capsule())
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
    }
}
