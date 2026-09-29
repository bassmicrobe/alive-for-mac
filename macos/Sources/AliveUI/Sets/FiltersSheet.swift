// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct FiltersSheet: View {
    var body: some View {
        SheetFrame(title: SetsStrings.filtersTitle.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
