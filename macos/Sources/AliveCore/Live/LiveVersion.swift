// Mac-only: version ordering for Live folder names (upstream's Version() flattened numbers only).
import Foundation

/// A Live version such as `12.0b20`, `11.3.20b1`, `11.3.35`, `10.1.41`. A release ranks above
/// its betas (`11.3.20` > `11.3.20b1`); betas of one number rank by their beta number.
public struct LiveVersion: Comparable, Hashable, Sendable {
    public let numbers: [Int]
    /// Beta number, nil for a release.
    public let beta: Int?

    public init(numbers: [Int], beta: Int?) {
        self.numbers = numbers
        self.beta = beta
    }

    public var isBeta: Bool { beta != nil }

    /// Parses the first dotted number in `text` and an optional `b<N>` suffix:
    /// "Live 12.0b20", "12.0b20", "Ableton Live 11.3.35 Suite" → ok; "Live" → nil.
    public init?(_ text: String) {
        let chars = Array(text)
        guard var i = chars.firstIndex(where: { $0.isASCII && $0.isNumber }) else { return nil }
        var nums: [Int] = []
        var current = 0, hasDigits = false
        func flush() { if hasDigits { nums.append(current) }; current = 0; hasDigits = false }
        while i < chars.count {
            let c = chars[i]
            if c.isASCII, let d = c.wholeNumberValue {
                current = current &* 10 &+ d; hasDigits = true
            } else if c == ".", hasDigits, i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isNumber {
                flush()
            } else {
                break
            }
            i += 1
        }
        flush()

        var betaNumber: Int?
        if i < chars.count, chars[i] == "b" {
            var n = 0, any = false
            var j = i + 1
            while j < chars.count, chars[j].isASCII, let d = chars[j].wholeNumberValue {
                n = n &* 10 &+ d; any = true; j += 1
            }
            if any { betaNumber = n }
        }
        self.init(numbers: nums, beta: betaNumber)
    }

    /// "Live 12.0b20" → 12.0b20
    public init?(folderName: String) {
        guard folderName.hasPrefix("Live ") else { return nil }
        self.init(String(folderName.dropFirst(5)))
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (beta.map { "b\($0)" } ?? "")
    }

    public static func < (a: LiveVersion, b: LiveVersion) -> Bool {
        let n = max(a.numbers.count, b.numbers.count)
        for i in 0..<n {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        switch (a.beta, b.beta) {
        case (nil, nil): return false
        case (nil, .some): return false        // a release is above its betas
        case (.some, nil): return true
        case let (x?, y?): return x < y
        }
    }
}
