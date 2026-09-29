// Mac-only: placeholder sheet for the project / sample folder lists (replaced by the Sets implementer).
import SwiftUI

struct RootsSheet: View {
    let kind: RootsKind

    var body: some View {
        SheetFrame(title: title, height: 260) {
            ComingSoonView(title: CommonStrings.comingSoonTitle.s)
        }
    }

    private var title: String {
        switch kind {
        case .projects: return SetsStrings.scanProjectsTitle.s
        case .samples: return SetsStrings.scanSamplesTitle.s
        }
    }
}
