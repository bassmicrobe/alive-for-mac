// Port of SamplesEmpty (src/SamplesTab.cs): the tab before any folder was chosen — what it is for,
// the folder picker, and Live's own folders as one-click suggestions.
import SwiftUI
import AliveCore

struct SamplesEmptyState: View {
    let model: SamplesModel

    var body: some View {
        let s = model.app.settings
        let suggestions = SampleRootSuggestions.make(env: model.app.catalog.env, projectRoots: s.roots,
                                                     existing: s.sampleRoots.filter { !s.disabledSampleRoots.contains($0) })
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                IconView(icon: .wave, size: 30, weight: .light)
                    .foregroundStyle(Theme.secondaryText)
                Text(SamplesStrings.emptyTitle.s)
                    .font(Theme.fHead)
                    .foregroundStyle(Theme.text)
                Text(SamplesStrings.emptyBody.s)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            PillButton(title: SamplesStrings.chooseFolders.s, icon: .plus, kind: .primary, action: choose)
            if !suggestions.isEmpty {
                SuggestionColumn(suggestions: suggestions) { model.addFolders([$0.path]) }
            }
            Text(SamplesStrings.manageHint.s)
                .font(Theme.fSmall)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func choose() {
        let picked = FolderPicker.chooseFolders(message: SamplesStrings.chooseFoldersMessage.s,
                                                prompt: CommonStrings.chooseFolderPrompt.s)
        if !picked.isEmpty { model.addFolders(picked) }
    }
}

private struct SuggestionColumn: View {
    let suggestions: [SampleRootSuggestion]
    let add: (SampleRootSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(CommonStrings.suggestionsTitle.s)
                .padding(.horizontal, 6)
            ForEach(suggestions) { s in
                SuggestionButton(suggestion: s) { add(s) }
            }
        }
        .frame(width: 460)
    }
}

private struct SuggestionButton: View {
    let suggestion: SampleRootSuggestion
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: 10) {
                IconView(icon: .folder, size: 13)
                    .foregroundStyle(Theme.secondaryText)
                Text(suggestion.title)
                    .font(Theme.fTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(suggestion.display())
                    .font(Theme.fSmall)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(CommonStrings.addSuggestion.s)
                    .font(Theme.fSmall)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: Theme.rowPillH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: Capsule())
        .rowHover()
        .help(suggestion.path)
    }
}
