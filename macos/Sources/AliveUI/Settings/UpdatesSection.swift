// Mac-only: PLACEHOLDER. Stage S5 replaces this with the update check (daily check toggle,
// "Check for updates", release notes link). Keep the type name and file: SettingsView embeds it.
import SwiftUI

struct UpdatesSection: View {
    var body: some View {
        Section(SettingsStrings.updatesTitle.s) {
            Text(SettingsStrings.updatesPlaceholder.s)
                .font(Theme.fBody)
                .foregroundStyle(Theme.textDim)
        }
    }
}
