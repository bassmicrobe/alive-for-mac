// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct PluginFiltersSheet: View {
    var body: some View {
        SheetFrame(title: PluginsStrings.filtersTitle.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
