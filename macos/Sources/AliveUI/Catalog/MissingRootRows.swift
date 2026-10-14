// Mac-only: a project root whose folder no longer exists (moved or deleted) is not "unreadable".
// One line per such root with the two ways out: pick the folder again, or drop it from the list.
import SwiftUI

struct MissingRootRows: View {
    let roots: [String]
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            ForEach(roots, id: \.self) { root in
                HStack(spacing: 10) {
                    Text(CommonStrings.rootMissingLine.f(SetFormat.homeAbbreviated(root)))
                        .font(Theme.fSmall).foregroundStyle(Theme.text)
                        .lineLimit(2).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(root)
                    PillButton(title: CommonStrings.chooseAgain.s, icon: .folder) { chooseAgain(root) }
                        .fixedSize()
                    PillButton(title: CommonStrings.removeFromList.s) { app.catalog.removeRoot(root) }
                        .fixedSize()
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func chooseAgain(_ root: String) {
        let picked = FolderPicker.chooseFolders(message: CommonStrings.chooseFolderMessage.s,
                                                prompt: CommonStrings.replaceFolderPrompt.s,
                                                allowsMultiple: false)
        guard let first = picked.first else { return }
        app.catalog.replaceRoot(root, with: first)
    }
}
