import XCTest
@testable import AliveUI

/// Every case of a string table has a non-empty English and Japanese text, and both use the same
/// multiset of format specifiers (`%@`, `%lld`, `%1$@`, `%%`, …).
func assertStringTableIsComplete<T: LocalizedStrings>(
    _ type: T.Type, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertFalse(T.allCases.isEmpty, "\(T.self) has no cases", file: file, line: line)
    for item in T.allCases {
        XCTAssertFalse(item.en.trimmingCharacters(in: .whitespaces).isEmpty,
                       "\(T.self).\(item): empty English text", file: file, line: line)
        XCTAssertFalse(item.ja.trimmingCharacters(in: .whitespaces).isEmpty,
                       "\(T.self).\(item): empty Japanese text", file: file, line: line)
        XCTAssertEqual(formatSpecifiers(in: item.en), formatSpecifiers(in: item.ja),
                       "\(T.self).\(item): en/ja format specifiers differ", file: file, line: line)
    }
}

/// Sorted list of the format specifiers found in `string`.
func formatSpecifiers(in string: String) -> [String] {
    let pattern = "%(?:\\d+\\$)?[-+ 0#]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfeEgGcCsSpaAF%]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(string.startIndex..., in: string)
    return regex.matches(in: string, range: range)
        .compactMap { Range($0.range, in: string).map { String(string[$0]) } }
        .sorted()
}

final class StringTableAssertionsTests: XCTestCase {
    func testSpecifierExtraction() {
        XCTAssertEqual(formatSpecifiers(in: "%1$@ of %2$lld — 100%%"), ["%%", "%1$@", "%2$lld"])
        XCTAssertEqual(formatSpecifiers(in: "no format"), [])
    }
}
