// Mac-only: the "Mac integration" section of the settings (Spotlight, menu bar, Finder tags).
import SwiftUI

struct IntegrationSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        Section(IntegrationStrings.sectionTitle.s) {
            Toggle(IntegrationStrings.spotlightToggle.s, isOn: $prefs.spotlight)
            help(IntegrationStrings.spotlightHelp.s)
            Toggle(IntegrationStrings.menuBarToggle.s, isOn: $prefs.menuBar)
            help(IntegrationStrings.menuBarHelp.s)
            Toggle(IntegrationStrings.finderTagsToggle.s, isOn: $prefs.finderTags)
            help(IntegrationStrings.finderTagsHelp.s)
        }
    }

    private func help(_ text: String) -> some View {
        Text(text)
            .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
