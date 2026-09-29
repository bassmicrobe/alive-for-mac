// Port of the arrangement picture shared by Home tiles and the Sets inspector (src/ThumbCache.cs,
// src/ArrangementRender.cs). Placeholder — the Home implementer replaces the body.
// Cross-feature entry point: keep `ArrangementThumbnailView(path:)`.
import SwiftUI

struct ArrangementThumbnailView: View {
    /// Path of the .als whose arrangement is drawn.
    let path: String

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.thumbR)
            .fill(Theme.surface)
    }
}
