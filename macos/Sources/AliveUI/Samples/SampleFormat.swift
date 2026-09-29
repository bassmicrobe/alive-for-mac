// Mac-only: text of the Samples cells and panel (upstream: the formatting in src/SamplesTab.cs).
import Foundation
import AliveCore

enum SampleFormat {
    /// "31,807" — grouped in the UI language.
    static func number(_ n: Int, locale: Locale = Localizer.shared.locale) -> String {
        n.formatted(.number.locale(locale))
    }

    /// "2026-08-28" in the local time zone; empty for an unknown date.
    static func day(_ date: Date?) -> String {
        guard let date, date > .distantPast else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// A project folder or a pack runs to gigabytes, and "3841 MB" reads worse than "3.75 GB": past
    /// a thousand megabytes it switches to gigabytes. Empty for nothing. (Upstream `SizeMB`.)
    static func megabytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1024 / 1024
        if mb >= 1024 {
            let gb = mb / 1024
            return SamplesStrings.sizeGB.f(String(format: gb >= 100 ? "%.0f" : "%.2f", gb))
        }
        return SamplesStrings.sizeMB.f(String(format: mb >= 100 ? "%.0f" : "%.1f", mb))
    }

    /// Kilobytes for a single sample; MB and GB for anything bigger. (Upstream `SampleSize`.)
    static func sampleSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        if bytes < 1024 * 1024 { return SamplesStrings.sizeKB.f(String(max(1, Int((Double(bytes) / 1024).rounded())))) }
        return megabytes(bytes)
    }

    /// "5 · 0.8%" for 5 of 612.
    static func share(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "" }
        let p = Double(part) * 100 / Double(whole)
        return String(format: p >= 10 ? "%.0f%%" : "%.1f%%", p)
    }

    /// "1:23" / "0:04.5" — a sample is usually short, so under ten seconds it shows tenths.
    static func duration(ms: Int) -> String {
        guard ms > 0 else { return "" }
        if ms < 10_000 { return String(format: "0:%04.1f", Double(ms) / 1000) }
        let s = ms / 1000
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "44.1 kHz · 24-bit · stereo"; empty when the header said nothing.
    static func format(_ h: AudioHeader) -> String {
        var parts: [String] = []
        if h.rate > 0 {
            var khz = String(format: "%.1f", Double(h.rate) / 1000)
            if khz.hasSuffix(".0") { khz.removeLast(2) }
            parts.append(SamplesStrings.formatKHz.f(khz))
        }
        if h.bits > 0 { parts.append(SamplesStrings.formatBits.f(h.bits)) }
        switch h.channels {
        case 1: parts.append(SamplesStrings.formatMono.s)
        case 2: parts.append(SamplesStrings.formatStereo.s)
        case 3...: parts.append(SamplesStrings.formatChannels.f(h.channels))
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// The name column's title in each view.
    static func nameTitle(lens: SampleLens, isFlat: Bool) -> String {
        if lens == .mostUsed || lens == .duplicates { return SamplesStrings.colSample.s }
        if lens == .neverUsed || !isFlat { return SamplesStrings.colFolder.s }
        return SamplesStrings.colName.s
    }

    static func title(of column: SampleColumn, lens: SampleLens, isFlat: Bool) -> String {
        switch column {
        case .name: return nameTitle(lens: lens, isFlat: isFlat)
        case .location: return SamplesStrings.colLocation.s
        case .samples: return SamplesStrings.colSamples.s
        case .used: return SamplesStrings.colUsed.s
        case .copies: return SamplesStrings.colCopies.s
        case .projects: return SamplesStrings.colProjects.s
        case .lastUsed: return SamplesStrings.colLastUsed.s
        case .created: return SamplesStrings.colCreated.s
        case .modified: return SamplesStrings.colModified.s
        case .size: return SamplesStrings.colSize.s
        }
    }

    static func title(of lens: SampleLens) -> String {
        switch lens {
        case .all: return SamplesStrings.lensAll.s
        case .neverUsed: return SamplesStrings.lensNeverUsed.s
        case .mostUsed: return SamplesStrings.lensMostUsed.s
        case .duplicates: return SamplesStrings.lensDuplicates.s
        }
    }
}
