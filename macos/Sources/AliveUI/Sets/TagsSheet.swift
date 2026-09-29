// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct TagsSheet: View {
    let path: String

    var body: some View {
        SheetFrame(title: SetsStrings.tagsTitle.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
