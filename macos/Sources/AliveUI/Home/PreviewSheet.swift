// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct PreviewSheet: View {
    let path: String

    var body: some View {
        SheetFrame(title: HomeStrings.previewTitle.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
