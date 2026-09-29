import SwiftUI
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Renders the Plugins tab and the filters sheet to PNG files without opening a window (no GUI
/// launch, no focus stolen). Gated: `ALIVE_TEST_SNAPSHOT=<output folder>`; the catalog comes from
/// `ALIVE_TEST_DATA=<data folder with index.cache>` (read only), else a small synthetic one.
@MainActor
final class PluginsSnapshotTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func app() throws -> AppModel {
        if let data = env["ALIVE_TEST_DATA"] {
            let app = AppModel(dataDir: data)
            app.catalog.index.loadFromCache()
            app.catalog.index.refreshInstalled()
            app.catalog.settingsDidChange()
            return app
        }
        return try makeModel()
    }

    private func png(_ view: some View, width: CGFloat, height: CGFloat, to path: String) throws {
        let framed = view
            .frame(width: width, height: height)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let data = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    func testRenderPluginsTabAndFiltersSheet() async throws {
        guard let out = env["ALIVE_TEST_SNAPSHOT"] else { throw XCTSkip("ALIVE_TEST_SNAPSHOT not set") }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let app = try app()
        app.tab = .plugins
        await app.plugins.settle()
        app.plugins.show(pluginNamed: env["ALIVE_TEST_PLUGIN"] ?? "Serum")
        try png(PluginsView().environment(app), width: 1180, height: 640, to: out + "/plugins.png")

        app.plugins.filter.statusMissing = true
        app.plugins.card = .missing
        try png(PluginsView().environment(app), width: 1180, height: 640, to: out + "/plugins-missing.png")
        app.plugins.resetFilters()

        app.plugins.filter.vendors = ["FabFilter"]
        try png(PluginFiltersSheet().environment(app), width: 640, height: 420, to: out + "/plugin-filters.png")
    }
}
