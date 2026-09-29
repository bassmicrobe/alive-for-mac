// Mac-only: placeholder sheet (replaced by the feature's implementer).
import SwiftUI

struct RescueSheet: View {
    let path: String

    var body: some View {
        SheetFrame(title: RescueStrings.title.s, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }
}
