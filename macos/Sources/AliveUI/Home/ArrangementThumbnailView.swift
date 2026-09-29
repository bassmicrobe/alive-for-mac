// Port of the arrangement picture shared by Home tiles and the Sets inspector (src/ThumbCache.cs,
// src/HomeView.cs picture loading). Cross-feature entry point: keep `ArrangementThumbnailView(path:)`.
import SwiftUI

struct ArrangementThumbnailView: View {
    /// Path of the .als whose arrangement is drawn.
    let path: String

    @Environment(AppModel.self) private var app
    @State private var result: ThumbResult?

    var body: some View {
        ZStack {
            Theme.sunken
            content
        }
        .aspectRatio(ThumbnailPipeline.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.thumbR, style: .continuous))
        // The picture is asked for when the view appears and abandoned when it goes off screen;
        // a re-saved set (new modification time) has a new key, so a rescan reloads it.
        .task(id: LoadKey(path: path, revision: app.catalog.revision)) { await load() }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch result {
        case .image(let picture):
            Image(decorative: picture.cgImage, scale: 1.5)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .transition(.opacity)
        case .empty:
            placeholder(HomeStrings.noArrangement.s)
        case .failed:
            placeholder(HomeStrings.thumbUnreadable.s)
        case .cancelled, nil:
            EmptyView()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Theme.fSmall)
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
    }

    private struct LoadKey: Hashable {
        let path: String
        let revision: Int
    }

    private func load() async {
        let pipeline = app.home.thumbnails
        // Memory only on the main thread; reading and decoding a PNG happens in `produce`.
        if let hit = pipeline.cachedInMemory(path) {
            result = hit
            return
        }
        let produced = await pipeline.produce(path)
        if Task.isCancelled { return }
        if case .cancelled = produced { return }
        withAnimation(.easeOut(duration: 0.18)) { result = produced }
    }
}
