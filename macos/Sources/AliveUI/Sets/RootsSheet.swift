// Mac-only: minimal project / sample folder list (wave 1.5) so ⇧⌘O works; the Sets implementer
// replaces it with the full dialog (counts, "from Live" suggestions, drag and drop).
import SwiftUI

struct RootsSheet: View {
    let kind: RootsKind
    @Environment(AppModel.self) private var app

    var body: some View {
        SheetFrame(title: title, height: 380) {
            VStack(alignment: .leading, spacing: 12) {
                Text(SetsStrings.rootsHint.s)
                    .font(Theme.fSmall)
                    .foregroundStyle(Theme.textDim)
                list
                HStack {
                    PillButton(title: SetsStrings.rootsAdd.s, icon: .plus, kind: .primary, action: add)
                    Spacer()
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .projects: return SetsStrings.scanProjectsTitle.s
        case .samples: return SetsStrings.scanSamplesTitle.s
        }
    }

    private var roots: [String] {
        kind == .projects ? app.settings.roots : app.settings.sampleRoots
    }

    private func isOn(_ root: String) -> Bool {
        let off = kind == .projects ? app.settings.disabledRoots : app.settings.disabledSampleRoots
        return !off.contains(root)
    }

    @ViewBuilder private var list: some View {
        if roots.isEmpty {
            Text(SetsStrings.rootsEmpty.s)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(roots, id: \.self) { root in row(root) }
                }
            }
        }
    }

    private func row(_ root: String) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isOn(root) }, set: { setRoot(root, enabled: $0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(SetsStrings.rootOffHelp.s)
            Text(root)
                .font(Theme.fBody)
                .foregroundStyle(isOn(root) ? Theme.text : Theme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            CircleIconButton(icon: .close, help: SetsStrings.rootRemoveHelp.s) { remove(root) }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.rowPillH)
        .background(Theme.surface, in: Capsule())
    }

    // MARK: - Edits

    private func add() {
        let picked = FolderPicker.chooseFolders(message: CommonStrings.chooseFolderMessage.s,
                                                prompt: CommonStrings.chooseFolderPrompt.s)
        guard !picked.isEmpty else { return }
        if kind == .projects {
            app.catalog.addRoots(picked)
        } else {
            editSamples { $0.sampleRoots = Self.appending(picked, to: $0.sampleRoots) }
        }
    }

    private func remove(_ root: String) {
        if kind == .projects {
            app.catalog.removeRoot(root)
        } else {
            editSamples {
                $0.sampleRoots.removeAll { $0 == root }
                $0.disabledSampleRoots.removeAll { $0 == root }
            }
        }
    }

    private func setRoot(_ root: String, enabled: Bool) {
        if kind == .projects {
            app.catalog.setRoot(root, enabled: enabled)
        } else {
            editSamples {
                $0.disabledSampleRoots.removeAll { $0 == root }
                if !enabled { $0.disabledSampleRoots.append(root) }
            }
        }
    }

    /// Sample roots belong to the Samples implementer's index: save, then ask it to rescan.
    private func editSamples(_ change: (inout AppSettings) -> Void) {
        app.mutateSettings(change)
        app.samples.rescan()
    }

    private static func appending(_ new: [String], to list: [String]) -> [String] {
        list + new.filter { path in !list.contains { $0.caseInsensitiveCompare(path) == .orderedSame } }
    }
}
