import CoreGraphics
import ImageIO
import XCTest
@testable import AliveCore
@testable import AliveRender

final class PreviewTrackFitTests: XCTestCase {
    func testQuickLookKeepsTheLastTrackWithinItsBitmapBudget() throws {
        for count in [69, 128, 400] {
            var arrangement = Arrangement()
            arrangement.end = 16
            arrangement.clipCount = 1
            arrangement.tracks = (0..<count).map { _ in TrackLane() }
            var clip = ClipBlock()
            clip.start = 0; clip.end = 16; clip.color = 14
            arrangement.tracks[count - 1].clips = [clip]
            let png = try XCTUnwrap(PreviewPage.pictureData(for: arrangement))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1500)
            XCTAssertLessThanOrEqual(image.height, 1100)
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // Only the final lane contains a clip. Grid pixels are much fainter than its fill.
            let lowerAlphas = ((image.height - 20)..<image.height).map { y in
                bytes[(y * image.width + image.width / 2) * 4 + 3]
            }
            XCTAssertTrue(lowerAlphas.contains { $0 >= 230 }, "Final track missing at \(count) tracks")
        }
    }
}
