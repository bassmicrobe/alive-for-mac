// Port of the sample column catalog (src/SamplesTab.cs: SampleCatalog, SampleViewDecides,
// SampleColumns) and of the column spec of src/MainForm.cs (LoadColumnSpec / ColumnSpec).
import Foundation

public enum SampleLens: String, CaseIterable, Sendable {
    case all, neverUsed, mostUsed, duplicates
}

/// The columns of the Samples tab. Raw values are the ids upstream writes into `samplecols`.
public enum SampleColumn: String, CaseIterable, Sendable {
    case name = "Name"
    case location = "Location"
    case samples = "Samples"
    case used = "Used"
    case copies = "Copies"
    case projects = "Projects"
    case lastUsed = "LastUsed"
    case created = "Created"
    case modified = "Modified"
    case size = "Size"

    /// Upstream's width in its logical pixels; 0 — takes whatever is left (the name and the
    /// location, cut in the middle: what tells two samples apart is at the end — "(7).wav").
    public var defaultWidth: Int {
        switch self {
        case .name, .location: return 0
        case .samples: return 130
        case .used: return 90
        case .copies: return 110
        case .projects: return 120
        case .lastUsed, .created, .modified: return 150
        case .size: return 130
        }
    }

    public var isRightAligned: Bool {
        switch self {
        case .samples, .used, .copies, .projects, .size: return true
        default: return false
        }
    }

    public var isPath: Bool { self == .name || self == .location }

    public static let defaults: [SampleColumn] = [.name, .location, .samples, .used, .projects, .lastUsed, .size]
    public static let mandatory = SampleColumn.name

    /// Whether the current view decides a column by itself: nil — it is the person's to turn on and
    /// off; false — never here (it would be the same in every row, or empty); true — always here,
    /// it is what the view is about.
    public func viewDecides(lens: SampleLens, isFlat: Bool) -> Bool? {
        let onlyFiles = lens == .mostUsed || lens == .duplicates
        switch self {
        case .location: return isFlat ? nil : false          // in the tree the tree is the location
        case .samples: return onlyFiles ? false : nil
        case .used: return onlyFiles || lens == .neverUsed ? false : nil
        case .projects, .lastUsed: return lens == .neverUsed ? false : nil   // "never" in every row
        case .copies: return lens == .duplicates ? true : nil
        case .created: return lens == .neverUsed ? true : nil                // how long it has lain there
        default: return nil
        }
    }
}

/// The person's columns: which are on, in what order and (for those they resized) how wide.
/// Parsed from "Name,Location,Samples:140,…" — the order of the tokens IS the order on screen.
public struct SampleColumnSpec: Equatable, Sendable {
    public var order: [SampleColumn]
    public var widths: [SampleColumn: Int]

    public init(order: [SampleColumn] = SampleColumn.defaults, widths: [SampleColumn: Int] = [:]) {
        self.order = order
        self.widths = widths
    }

    public init(spec: String) {
        var order: [SampleColumn] = []
        var widths: [SampleColumn: Int] = [:]
        for token in spec.split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespaces)
            var idText = t
            var width = -1
            if let colon = t.firstIndex(of: ":"), colon != t.startIndex {
                idText = String(t[..<colon])
                width = Int(t[t.index(after: colon)...]) ?? -1
            }
            // A column from another version of the program, or one already listed — skip it.
            guard let id = SampleColumn.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(idText) == .orderedSame }),
                  !order.contains(id) else { continue }
            order.append(id)
            if width > 0 { widths[id] = width }
        }
        if !order.contains(SampleColumn.mandatory) { order.insert(SampleColumn.mandatory, at: 0) }
        if order.count <= 1 { order = SampleColumn.defaults; widths = [:] }
        self.init(order: order, widths: widths)
    }

    /// Text for `settings.sampleColumns`. A stretching column never gets a width (it always takes
    /// the remainder), nor does one left at its default.
    public var spec: String {
        order.map { c in
            if c.defaultWidth != 0, let w = widths[c], w > 0, w != c.defaultWidth { return "\(c.rawValue):\(w)" }
            return c.rawValue
        }.joined(separator: ",")
    }

    public func width(of c: SampleColumn) -> Int {
        c.defaultWidth == 0 ? 0 : (widths[c].flatMap { $0 > 0 ? $0 : nil } ?? c.defaultWidth)
    }

    /// Switches a column on (at its place in the catalog) or off. The name cannot go.
    public func toggling(_ c: SampleColumn) -> SampleColumnSpec {
        guard c != SampleColumn.mandatory else { return self }
        var next = self
        if let i = next.order.firstIndex(of: c) {
            next.order.remove(at: i)
        } else {
            let all = SampleColumn.allCases
            let rank = all.firstIndex(of: c) ?? 0
            let at = next.order.firstIndex { (all.firstIndex(of: $0) ?? 0) > rank } ?? next.order.count
            next.order.insert(c, at: at)
        }
        return next
    }

    /// The columns of the current view: the person's, in their order, less what the view hides,
    /// plus what it adds — at its place in the catalog.
    public func visible(lens: SampleLens, isFlat: Bool) -> [SampleColumn] {
        var cols = order.filter { $0.viewDecides(lens: lens, isFlat: isFlat) != false }
        let all = SampleColumn.allCases
        for (k, d) in all.enumerated() where d.viewDecides(lens: lens, isFlat: isFlat) == true && !cols.contains(d) {
            let at = cols.firstIndex { (all.firstIndex(of: $0) ?? 0) > k } ?? cols.count
            cols.insert(d, at: at)
        }
        return cols
    }
}
