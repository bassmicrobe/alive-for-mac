import AppKit
import SwiftUI
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Lays the Home tab out inside a real (never shown) window: catches view-graph crashes that only
/// the display cycle finds.
@MainActor
final class HomeHostingTests: XCTestCase {
    func testHomeLaysOutInAWindowWithoutRaising() async throws {
        let scratch = makeHomeScratch()
        scratch.write("data/settings.cfg", "root=\(scratch.sub("lib"))\n")
        _ = try scratch.writeSet("lib/A Project/a.als")
        _ = try scratch.writeSet("lib/B Project/b.als", withClip: false)
        let app = AppModel(dataDir: scratch.sub("data"))
        app.start()
        for _ in 0..<80 where !app.catalog.isReady { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(app.catalog.sets.count, 2)
        app.selectedSetPath = app.catalog.sets.first?.path

        let host = NSHostingView(rootView: HomeView().environment(app).frame(width: 1200, height: 800))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1200, height: 800),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            window.displayIfNeeded()
        }
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    /// Gated: the whole main window over a real library (read-only), for a few seconds.
    func testMainWindowOverARealLibrary() async throws {
        guard let root = ProcessInfo.processInfo.environment["ALIVE_TEST_HOST_ROOT"] else {
            throw XCTSkip("ALIVE_TEST_HOST_ROOT not set")
        }
        let scratch = makeHomeScratch()
        scratch.write("data/settings.cfg", "root=\(root)\n")
        let app = AppModel(dataDir: scratch.sub("data"))
        app.start()
        let host = NSHostingView(rootView: MainWindow().environment(app))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1240, height: 780),
                              styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = host
        window.orderFrontRegardless()
        for _ in 0..<400 {
            try await Task.sleep(nanoseconds: 50_000_000)
            window.displayIfNeeded()
        }
        XCTAssertGreaterThan(app.catalog.sets.count, 0)
    }
}
