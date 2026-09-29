// Mac-only: placeholder view (replaced by the feature's implementer). Keeps the first-run
// screen: with no project folder set the Home tab offers to add one.
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.catalog.hasEnabledRoots {
            ComingSoonView(title: HomeStrings.title.s)
        } else {
            RootsEmptyState()
        }
    }
}
