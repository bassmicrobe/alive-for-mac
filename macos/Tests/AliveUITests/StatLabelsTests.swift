import XCTest
import AliveCore
@testable import AliveUI

final class StatLabelsTests: XCTestCase {
    private let size = CGSize(width: 640, height: 640)
    private func measure(_ text: String, _ isTitle: Bool) -> CGSize {
        CGSize(width: Double(text.count) * 6.5, height: isTitle ? 15 : 13)
    }

    private func scene() -> CloudScene {
        let s = CloudScene(metrics: Metrics())
        s.setData((0..<40).map { statSet("s\($0)", tracks: 2 + $0) })
        return s
    }

    func testCaptionsStayOutsideTheDataZone() {
        let s = scene()
        for preset in CameraPreset.allCases {
            s.camera.setPreset(preset)
            let zone = CloudAxisLabels.DataZone(proj: s.camera.projector(size: size), reach: CloudAxisLabels.reach(s))
            let labels = CloudAxisLabels.layout(scene: s, size: size, titles: ["X · Tracks", "Y · Plugins", "Z · BPM"],
                                                measure: measure)
            XCTAssertFalse(labels.isEmpty, "\(preset): titles are placed")
            for l in labels {
                let sz = measure(l.text, l.isTitle)
                let r = CGRect(x: l.center.x - sz.width / 2, y: l.center.y - sz.height / 2, width: sz.width, height: sz.height)
                XCTAssertFalse(zone.covers(r), "\(preset): \(l.text) lies over the data")
            }
        }
    }

    func testFrontViewKeepsCaptionsInsideTheCanvas() {
        let s = scene()
        s.camera.setPreset(.front)
        let labels = CloudAxisLabels.layout(scene: s, size: size, titles: ["X · Tracks", "Y · Plugins", "Z · BPM"],
                                            measure: measure)
        let canvas = CGRect(origin: .zero, size: size)
        for l in labels where l.isTitle {
            let sz = measure(l.text, true)
            let r = CGRect(x: l.center.x - sz.width / 2, y: l.center.y - sz.height / 2, width: sz.width, height: sz.height)
            XCTAssertTrue(canvas.contains(r), "\(l.text) at \(r)")
        }
    }

    func testFittedEllipsizesOrDropsClipNames() {
        XCTAssertEqual(ChartText.fitted("Kick", size: 11, maxWidth: 400), "Kick")
        let cut = ChartText.fitted("A very long clip name indeed", size: 11, maxWidth: 60)
        XCTAssertNotNil(cut)
        XCTAssertTrue(cut?.hasSuffix("…") ?? false)
        XCTAssertLessThanOrEqual(ChartText.width(cut ?? "", size: 11), 60)
        XCTAssertNil(ChartText.fitted("Kick", size: 11, maxWidth: 8))
    }
}
