// Mac-only: the Help sheet's short note on the menu bar and Spotlight (kept out of HelpSheet.swift).
import SwiftUI

struct IntegrationHelpCard: View {
    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(IntegrationStrings.helpTitle.s).font(Theme.fTitle).foregroundStyle(Theme.text)
                Text(IntegrationStrings.helpMenuBar.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
                Text(IntegrationStrings.helpSpotlight.s).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
