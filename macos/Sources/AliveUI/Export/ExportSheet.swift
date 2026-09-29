// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct ExportSheet: View {
    let path: String

    var body: some View {
        SheetFrame(title: ExportStrings.title.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
