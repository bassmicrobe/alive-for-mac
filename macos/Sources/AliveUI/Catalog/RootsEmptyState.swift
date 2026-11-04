// Mac-only: the first-run screen (upstream: the empty catalog + RootsDialog). Shown by the Home and
// Sets tabs while no project folder is set: one button to pick folders, and one-click suggestions
// found from Live's own configuration.
import SwiftUI

struct RootsEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let suggestions = RootSuggestions.make(env: app.catalog.env, existingRoots: app.settings.roots)
        VStack(spacing: Theme.s(22)) {
            VStack(spacing: Theme.s(10)) {
                IconView(icon: .folder, size: 30, weight: .light)
                    .foregroundStyle(Theme.textDim)
                Text(CommonStrings.emptyRootsTitle.s)
                    .font(Theme.fHead)
                    .foregroundStyle(Theme.text)
                Text(CommonStrings.emptyRootsBody.s)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Theme.s(380))
            }
            PillButton(title: CommonStrings.addProjectsFolder.s, icon: .plus, kind: .primary) {
                chooseFolders()
            }
            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions) { app.catalog.addRoot($0.path) }
            }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolders() {
        let picked = FolderPicker.chooseFolders(message: CommonStrings.chooseFolderMessage.s,
                                                prompt: CommonStrings.chooseFolderPrompt.s)
        if !picked.isEmpty { app.catalog.addRoots(picked) }
    }
}

private struct SuggestionList: View {
    let suggestions: [RootSuggestion]
    let add: (RootSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(6)) {
            SectionHeader(CommonStrings.suggestionsTitle.s)
                .padding(.horizontal, Theme.s(6))
            ForEach(suggestions) { suggestion in
                SuggestionRow(suggestion: suggestion) { add(suggestion) }
            }
        }
        .frame(width: Theme.s(420))
    }
}

private struct SuggestionRow: View {
    let suggestion: RootSuggestion
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.s(10)) {
                IconView(icon: .folder, size: 13)
                    .foregroundStyle(Theme.textDim)
                Text(suggestion.display())
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Theme.s(8))
                Text(CommonStrings.addSuggestion.s)
                    .font(Theme.fSmall)
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, Theme.s(14))
            .frame(height: Theme.rowPillH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: Capsule())
        .rowHover()
        .help(suggestion.path)
    }
}
