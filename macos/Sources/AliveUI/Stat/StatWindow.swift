// Mac-only: placeholder for the Stat window (`Window(id: "stat")`).
import SwiftUI

struct StatWindow: View {
    var body: some View {
        ComingSoonView(title: StatStrings.title.s)
            .frame(minWidth: 520, minHeight: 360)
            .background(Theme.bg)
    }
}
