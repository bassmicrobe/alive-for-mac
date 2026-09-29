import XCTest
import AppKit
import SwiftUI
@testable import AliveUI

final class ThemeTests: XCTestCase {
    func testEveryIconSymbolExists() {
        for icon in AppIcon.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil),
                            "missing SF Symbol \(icon.symbol) for \(icon)")
        }
    }

    func testHexColorComponents() {
        let color = NSColor(Color(hex: 0x1B1B1D)).usingColorSpace(.sRGB)
        XCTAssertEqual(color?.redComponent ?? 0, 0x1B / 255.0, accuracy: 0.002)
        XCTAssertEqual(color?.blueComponent ?? 0, 0x1D / 255.0, accuracy: 0.002)
    }
}
