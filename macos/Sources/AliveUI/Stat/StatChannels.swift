// Port of nebula/Channels.cs (Metric, Metrics, Range). Foundation only: no SwiftUI here.
import Foundation
import AliveCore

/// How a metric is coloured when it sits in the colour channel.
enum ColorMode: Equatable {
    /// A continuous gradient.
    case ramp
    /// A palette by class number.
    case classes
    /// The circle of fifths: key → hue.
    case key
}

/// One value of a set that can be plugged into any of the cloud's six channels. The value is
/// always a number: position along an axis, size, transparency and colour are all computed from
/// it the same way. NaN means "this set does not have one" — not zero: a set from Live 10 has no
/// key at all, and putting it at the start of the scale would be a lie.
struct Metric {
    let id: String
    let title: StatStrings
    /// The scale is logarithmic. Needed where the tail stretches over orders of magnitude: folder
    /// sizes and sample reference counts differ by thousands of times.
    var isLog = false
    /// The value is a class number rather than a quantity: key, scale, shelf. In colour these are
    /// painted with a palette rather than a gradient.
    var isCategorical = false
    var color = ColorMode.ramp
    let value: (SetEntry) -> Double
    let text: (SetEntry) -> String
}

/// Shelves are numbered by first appearance: folder names are not known in advance, while a
/// class's colour has to stay the same for the whole session. One registry per window, not a
/// static, so the numbering is deterministic and tests do not share it.
final class PlaceRegistry {
    private var indexByName: [String: Int] = [:]

    func index(of place: String) -> Int {
        let key = place.lowercased()
        if let i = indexByName[key] { return i }
        let i = indexByName.count
        indexByName[key] = i
        return i
    }
}

struct Metrics {
    let all: [Metric]

    /// Ids in upstream's order — the order of the drop-down lists.
    static let ids = ["tracks", "plugins", "bpm", "key", "scale", "projsize", "setsize", "files",
                      "missfiles", "missplugins", "modified", "created", "live", "place", "name", "scatter"]

    init(places: PlaceRegistry = PlaceRegistry()) {
        all = Metrics.build(places: places)
    }

    /// The metric with this id, or the first one for an unknown id.
    func byId(_ id: String) -> Metric { all.first { $0.id == id } ?? all[0] }

    func index(of id: String) -> Int { all.firstIndex { $0.id == id } ?? 0 }

    // MARK: catalog

    private static func build(places: PlaceRegistry) -> [Metric] {
        let nan = Double.nan
        var key = Metric(id: "key", title: .metricKey,
                         value: { $0.scaleRoot >= 0 ? Double($0.scaleRoot) : nan },
                         text: { $0.key.isEmpty ? "—" : $0.key })
        // A key as a number is a note number, not a "how much". Along an axis it gives twelve
        // planes; in colour, the circle of fifths (see Palette.key).
        key.isCategorical = true
        key.color = .key

        var scale = Metric(id: "scale", title: .metricScale,
                           value: { $0.scaleIndex >= 0 ? Double($0.scaleIndex) : nan },
                           text: { $0.scaleIndex >= 0 ? Scales.scaleName($0.scaleIndex) : "—" })
        scale.isCategorical = true
        scale.color = .classes

        var place = Metric(id: "place", title: .metricCollection,
                           value: { $0.place.isEmpty ? nan : Double(places.index(of: $0.place)) },
                           text: { $0.place.isEmpty ? "—" : $0.place })
        place.isCategorical = true
        place.color = .classes

        var projSize = Metric(id: "projsize", title: .metricProjectSize,
                              value: { $0.projectSize > 0 ? Double($0.projectSize) : nan },
                              text: { $0.projectSize > 0 ? bytes($0.projectSize) : "…" })
        projSize.isLog = true
        var setSize = Metric(id: "setsize", title: .metricSetSize,
                             value: { $0.size > 0 ? Double($0.size) : nan },
                             text: { bytes($0.size) })
        setSize.isLog = true
        var files = Metric(id: "files", title: .metricSampleRefs,
                           value: { Double($0.totalRefs) }, text: { String($0.totalRefs) })
        files.isLog = true

        return [
            Metric(id: "tracks", title: .metricTracks,
                   value: { $0.tracks > 0 ? Double($0.tracks) : nan },
                   text: { $0.tracks > 0 ? String($0.tracks) : "—" }),
            Metric(id: "plugins", title: .metricPlugins,
                   value: { Double($0.plugins.count) }, text: { String($0.plugins.count) }),
            Metric(id: "bpm", title: .metricBPM,
                   value: { $0.tempo > 0 ? $0.tempo : nan },
                   text: { $0.tempo > 0 ? tempoText($0.tempo) : "—" }),
            key, scale, projSize, setSize, files,
            Metric(id: "missfiles", title: .metricMissingFiles,
                   value: { Double($0.missingFiles) }, text: { String($0.missingFiles) }),
            Metric(id: "missplugins", title: .metricMissingPlugins,
                   value: { Double($0.missingPlugins) }, text: { String($0.missingPlugins) }),
            Metric(id: "modified", title: .metricModified,
                   value: { days($0.modified) }, text: { dateText($0.modified) }),
            Metric(id: "created", title: .metricCreated,
                   value: { days($0.created) }, text: { dateText($0.created) }),
            Metric(id: "live", title: .metricLiveVersion,
                   value: { version($0.shortVersion) },
                   text: { $0.shortVersion.isEmpty ? "—" : $0.shortVersion }),
            place,
            Metric(id: "name", title: .metricName,
                   value: { alphabetical($0.name) }, text: { $0.name }),
            Metric(id: "scatter", title: .metricScatter,
                   value: { hash01($0.path) }, text: { _ in "—" }),
        ]
    }

    // MARK: conversions

    private static let epoch1990: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 631_152_000)
    }()

    /// Days since 1990. A date as a number — so the scale is computed like any other value's.
    /// NaN for "no date" (the catalog's `distantPast`) and for anything before 1990.
    static func days(_ date: Date) -> Double {
        guard date >= epoch1990 else { return .nan }
        return date.timeIntervalSince(epoch1990) / 86_400
    }

    static func dateText(_ date: Date) -> String {
        guard date >= epoch1990 else { return "—" }
        return dayFormatter.string(from: date)
    }

    /// `yyyy-MM-dd` in local time: compact and language-neutral, so axis labels need no locale.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "12.3.5" → 12.0305: versions have to compare part by part, not as strings.
    static func version(_ v: String) -> Double {
        guard !v.isEmpty else { return .nan }
        var result = 0.0, weight = 1.0
        for part in v.split(separator: ".", omittingEmptySubsequences: false).prefix(3) {
            guard let n = Int(part) else { break }
            result += Double(n) * weight
            weight /= 100
        }
        return result > 0 ? result : .nan
    }

    static func tempoText(_ bpm: Double) -> String {
        let rounded = (bpm * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func bytes(_ b: Int64) -> String {
        if b <= 0 { return "—" }
        if b >= 1_073_741_824 { return String(format: "%.1f GB", Double(b) / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.0f MB", Double(b) / 1_048_576) }
        return String(format: "%.0f KB", Double(b) / 1024)
    }

    /// A name as a number: the first six characters in base 40, so that an "A→Z" axis is genuinely
    /// alphabetical rather than random.
    static func alphabetical(_ name: String) -> Double {
        if name.isEmpty { return 0 }
        let units = Array(name.lowercased().utf16)
        var v = 0.0
        for i in 0..<6 {
            var c = 0
            if i < units.count {
                let u = units[i]
                if u >= 97 && u <= 122 { c = Int(u) - 97 + 1 }
                else if u >= 48 && u <= 57 { c = 27 + Int(u) - 48 }
                else { c = 38 }
            }
            v = v * 40 + Double(c)
        }
        return v
    }

    /// A stable 0..1 number out of a string — for scattering dots where there is no value of their
    /// own. Ours rather than `hashValue`: that one is seeded per run, and the cloud would jump on
    /// every start.
    static func hash01(_ s: String) -> Double {
        Double(hash(s) & 0xFFFFFF) / Double(0x1000000)
    }

    /// FNV-1a over the lower-cased UTF-16 units, as upstream (`int` arithmetic that wraps).
    static func hash(_ s: String) -> Int {
        if s.isEmpty { return 0 }
        var h: UInt32 = 2_166_136_261
        for u in s.lowercased().utf16 { h = (h ^ UInt32(u)) &* 16_777_619 }
        return Int(h & 0x7FFF_FFFF)
    }
}

/// The scale of one value over the current set of sets. The edges are taken not from the minimum
/// and maximum but from the 2nd and 98th percentile: one 40 GB monster of a project would
/// otherwise squash all the rest into a dot at zero.
struct ValueRange: Equatable {
    var lo = 0.0
    var hi = 0.0
    var isLog = false
    var isEmpty = true

    init() {}

    init(sets: [SetEntry], metric m: Metric) {
        isLog = m.isLog
        var v: [Double] = []
        v.reserveCapacity(sets.count)
        for s in sets {
            let d = m.value(s)
            if d.isNaN { continue }
            v.append(m.isLog ? log10(1 + max(0, d)) : d)
        }
        guard !v.isEmpty else { return }
        v.sort()
        isEmpty = false
        // Percentiles are of no use for categories: every class has to land on the scale,
        // including the single set in a rare mode.
        if m.isCategorical || v.count < 20 {
            lo = v[0]; hi = v[v.count - 1]
        } else {
            lo = v[Int(Double(v.count) * 0.02)]
            hi = v[Int(Double(v.count) * 0.98)]
        }
        if hi - lo < 1e-9 { lo -= 0.5; hi += 0.5 }
    }

    /// 0…1 with clamping at the edges. NaN in — NaN out.
    func norm(_ raw: Double) -> Double {
        if raw.isNaN || isEmpty { return .nan }
        let v = isLog ? log10(1 + max(0, raw)) : raw
        return min(1, max(0, (v - lo) / (hi - lo)))
    }

    /// The value at the edge of the scale — for the axis labels.
    func at(_ t: Double) -> Double {
        let v = lo + (hi - lo) * t
        return isLog ? pow(10, v) - 1 : v
    }
}

/// A channel of the cloud: a metric, its scale, the edge labels — and whether it is on at all.
struct Axis {
    var metric: Metric
    /// A channel that is off takes no part in the cloud but remembers its value: switch it back
    /// on and it is already chosen.
    var isOn = true
    var range = ValueRange()
    var loText = ""
    var hiText = ""

    init(metric: Metric) { self.metric = metric }

    /// Computes the scale and the labels of its two edges over `sets` (the same 2nd/98th
    /// percentile rule as the scale, so the label names a set that really sits at the edge).
    mutating func fit(_ sets: [SetEntry]) {
        range = ValueRange(sets: sets, metric: metric)
        loText = ""; hiText = ""
        let m = metric
        let ok = sets.filter { !m.value($0).isNaN }.sorted { m.value($0) < m.value($1) }
        guard !ok.isEmpty else { return }
        let edgeToEdge = m.isCategorical || ok.count < 20
        let lo = edgeToEdge ? 0 : Int(Double(ok.count) * 0.02)
        let hi = min(ok.count - 1, edgeToEdge ? ok.count - 1 : Int(Double(ok.count) * 0.98))
        loText = m.text(ok[lo])
        hiText = m.text(ok[hi])
    }

    /// The channel is off — the scale is not computed and the edge is not labelled.
    mutating func clear() {
        range = ValueRange()
        loText = ""; hiText = ""
    }
}
