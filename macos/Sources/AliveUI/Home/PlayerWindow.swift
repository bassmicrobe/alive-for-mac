// Mac-only: placeholder for the player window (`Window(id: "player")`).
import SwiftUI

struct PlayerWindow: View {
    var body: some View {
        ComingSoonView(title: CommonStrings.windowPlayer.s)
            .frame(minWidth: 420, minHeight: 240)
            .background(Theme.bg)
    }
}
