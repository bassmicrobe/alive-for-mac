// Port of LoadChannels / SaveChannels in nebula/NebulaForm.cs: `nebula.cfg`, in upstream's format.
import Foundation
import AliveCore

/// What each of the six channels shows, whether it is on, and the look of the dots. Kept in
/// `nebula.cfg` (Nebula is the folder upstream's Stat window lives in) as `key=value` lines.
struct NebulaConfig: Equatable {
    static let channelKeys = ["x", "y", "z", "size", "fade", "colour"]
    static let defaultIds = ["tracks", "plugins", "bpm", "setsize", "created", "live"]

    /// The px ranges the Size sliders map 0…1 into, and the defaults.
    static let minSizeRange = 0.0...12.0
    static let maxSizeRange = 4.0...48.0

    var ids = NebulaConfig.defaultIds
    var isOn = [Bool](repeating: true, count: 6)
    var spin = false
    /// Round-tripped only: upstream reads it but pins the dot softness to 0.04 and offers no slider.
    var blur = 0.04
    var minFade = 0.08
    var maxFade = 1.0
    var minSize = 1.0
    var maxSize = 16.0
    var gradientId = Palette.gradients[0].id
    /// Lines this build does not know, kept in file order and written back.
    var unknownLines: [String] = []

    init() {}

    static let header = "# Nebula — what each channel shows, and whether it's on"

    // MARK: parse

    init(lines: [String]) {
        for raw in lines {
            guard let eq = raw.firstIndex(of: "=") else { continue }
            let key = raw[..<eq].trimmingCharacters(in: .whitespaces)
            let val = raw[raw.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !apply(key: key, value: val), !raw.hasPrefix("#") { unknownLines.append(raw) }
        }
        normalize()
    }

    private mutating func apply(key: String, value v: String) -> Bool {
        for (i, k) in NebulaConfig.channelKeys.enumerated() {
            if key == k { ids[i] = v; return true }
            if key == k + "_on" { isOn[i] = v != "0"; return true }
        }
        switch key {
        case "spin": spin = v == "1"
        case "blur": blur = Double(v) ?? blur
        case "minfade": minFade = Double(v) ?? minFade
        case "maxfade": maxFade = Double(v) ?? maxFade
        case "minsize": minSize = Double(v) ?? minSize
        case "maxsize": maxSize = Double(v) ?? maxSize
        case "gradient": gradientId = v
        default: return false
        }
        return true
    }

    /// Puts every value back into what the window can show: an id from another version falls
    /// back to Tracks, a gradient to Nebula, the sliders' ranges are enforced (and NaN dropped).
    mutating func normalize() {
        ids = ids.map { Metrics.ids.contains($0) ? $0 : "tracks" }
        if !Palette.gradients.contains(where: { $0.id == gradientId }) { gradientId = Palette.gradients[0].id }
        func clamp(_ v: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(r.upperBound, max(r.lowerBound, v)) : fallback
        }
        minFade = clamp(minFade, 0...1, 0.08)
        maxFade = clamp(maxFade, 0...1, 1)
        minSize = clamp(minSize, NebulaConfig.minSizeRange, 1)
        maxSize = clamp(maxSize, NebulaConfig.maxSizeRange, 16)
        blur = clamp(blur, 0...1, 0.04)
    }

    // MARK: serialize

    func serialized() -> String {
        var out = [NebulaConfig.header]
        for (i, k) in NebulaConfig.channelKeys.enumerated() {
            out.append("\(k)=\(ids[i])")
            out.append("\(k)_on=\(isOn[i] ? "1" : "0")")
        }
        out.append("spin=\(spin ? "1" : "0")")
        out.append("blur=\(Self.number(blur, decimals: 3))")
        out.append("minfade=\(Self.number(minFade, decimals: 3))")
        out.append("maxfade=\(Self.number(maxFade, decimals: 3))")
        out.append("minsize=\(Self.number(minSize, decimals: 2))")
        out.append("maxsize=\(Self.number(maxSize, decimals: 2))")
        out.append("gradient=\(gradientId)")
        out.append(contentsOf: unknownLines)
        return out.joined(separator: "\n") + "\n"
    }

    /// Invariant "0.###": no trailing zeros, no locale.
    static func number(_ v: Double, decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    // MARK: file

    static func path(dir: String) -> String { AppHome.file("nebula.cfg", in: dir) }

    /// Reads `nebula.cfg` from `dir`; defaults when it is missing.
    static func load(dir: String) -> NebulaConfig {
        guard let lines = AppHome.readLines(path(dir: dir)) else { return NebulaConfig() }
        return NebulaConfig(lines: lines)
    }

    func save(dir: String) throws {
        try AppHome.writeAtomically(serialized(), to: NebulaConfig.path(dir: dir))
    }
}
