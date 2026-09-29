import AVFoundation
import XCTest
@testable import AliveCore
@testable import AliveUI

/// A unique scratch folder, removed after the test.
final class HomeScratch {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "alive-home-tests-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func sub(_ rel: String) -> String { path + "/" + rel }

    @discardableResult
    func write(_ rel: String, _ text: String = "x") -> String {
        let p = sub(rel)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: URL(fileURLWithPath: p))
        return p
    }

    func setModified(_ path: String, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    /// A gzipped set with one audio clip on one track.
    @discardableResult
    func writeSet(_ rel: String, withClip: Bool = true) throws -> String {
        let p = sub(rel)
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Gzip.compress(Data(HomeFixtures.setXML(withClip: withClip).utf8)).write(to: URL(fileURLWithPath: p))
        return p
    }

    /// A 16-bit mono WAV of `seconds`, silent unless `amplitude` is set (never played: only decoded).
    /// The header is written by hand: AVAudioFile's writer needs the audio server, which is not
    /// there in every test environment.
    @discardableResult
    func writeWav(_ rel: String, seconds: Double = 1, rate: Double = 8000, amplitude: Float = 0) throws -> String {
        let p = sub(rel)
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let frames = Int(seconds * rate)
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let v = Int16(amplitude * Float(Int16.max) * sin(Float(i) * 0.05))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        var wav = Data("RIFF".utf8)
        wav += le32(36 + pcm.count) + Data("WAVEfmt ".utf8) + le32(16) + le16(1) + le16(1)
        wav += le32(Int(rate)) + le32(Int(rate) * 2) + le16(2) + le16(16)
        wav += Data("data".utf8) + le32(pcm.count) + pcm
        try wav.write(to: URL(fileURLWithPath: p))
        return p
    }

    func cleanup() { try? FileManager.default.removeItem(atPath: path) }
}

enum HomeFixtures {
    static func setXML(withClip: Bool) -> String {
        let clip = "<AudioClip Id=\"1\" Time=\"0\"><CurrentStart Value=\"0\"/><CurrentEnd Value=\"16\"/>"
            + "<Loop><LoopStart Value=\"0\"/><LoopEnd Value=\"16\"/><StartRelative Value=\"0\"/><LoopOn Value=\"false\"/></Loop>"
            + "<Name Value=\"a\"/><Color Value=\"5\"/><Disabled Value=\"false\"/></AudioClip>"
        let arranger = "<DeviceChain><MainSequencer><Sample><ArrangerAutomation><Events>\(withClip ? clip : "")</Events>"
            + "</ArrangerAutomation></Sample></MainSequencer></DeviceChain>"
        let track = "<AudioTrack Id=\"1\"><Name><EffectiveName Value=\"T\"/></Name><Color Value=\"5\"/>\(arranger)</AudioTrack>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<Ableton MajorVersion=\"5\" MinorVersion=\"12.0_12300\" Creator=\"Ableton Live 12.3.5\">"
            + "<LiveSet><Tracks>\(track)</Tracks>"
            + "<MainTrack Id=\"9\"><DeviceChain><Mixer><Tempo><LomId Value=\"0\"/><Manual Value=\"120\"/></Tempo></Mixer></DeviceChain></MainTrack>"
            + "</LiveSet></Ableton>"
    }
}

extension XCTestCase {
    func makeHomeScratch() -> HomeScratch {
        let s = HomeScratch()
        addTeardownBlock { s.cleanup() }
        return s
    }
}
