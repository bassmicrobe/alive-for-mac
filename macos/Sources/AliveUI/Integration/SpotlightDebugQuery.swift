// Mac-only, for automated QA: ALIVE_DEBUG_SPOTLIGHT_QUERY=<text> logs how many of Alive's own
// Spotlight items match <text> (a CSSearchQuery only sees the items of its own app, which
// `mdfind` cannot confirm). Does nothing when the variable is not set.
import CoreSpotlight
import Foundation
import AliveCore

enum SpotlightDebugQuery {
    static var text: String? {
        let value = ProcessInfo.processInfo.environment["ALIVE_DEBUG_SPOTLIGHT_QUERY"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Asks the index after a short delay (indexing is asynchronous) and logs the number of hits.
    static func logMatches(for text: String, after delay: TimeInterval = 4) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let query = CSSearchQuery(queryString: "title == \"*\(escaped)*\"cd", queryContext: nil)
        var hits = 0
        query.foundItemsHandler = { hits += $0.count }
        query.completionHandler = { error in
            Diag.info("spotlight-query '\(text)': \(hits) hits" + (error.map { " (error \($0))" } ?? ""))
        }
        Diag.info("spotlight-query armed")
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            Diag.info("spotlight-query start")
            query.start()
        }
    }
}
