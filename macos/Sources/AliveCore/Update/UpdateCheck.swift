// Port of src/UpdateCheck.cs (this fork's releases, not upstream's: those are Windows builds)
import Foundation

/// Asking GitHub what the newest release is — the only place in the program that touches the
/// network at all.
///
/// What goes out is an ordinary GET for a public page. Nothing about the person, the library or
/// the machine is sent: no identifier, no set names, no counters. What comes back is a version
/// and a link. The other end learns what any web server learns from anybody who opens a page —
/// an address and a time — and the switch in the settings turns even that off.
public enum UpdateCheck {
    public static let latestURL = "https://api.github.com/repos/bassmicrobe/alive-for-mac/releases/latest"
    /// Where to send somebody when the answer could not be read: the releases page.
    public static let pageURL = "https://github.com/bassmicrobe/alive-for-mac/releases"
    public static let timeout: TimeInterval = 8

    /// How much newer the release out there is.
    public enum Step: Equatable, Sendable {
        /// Nothing to offer: the same version, an older one, or an answer we could not read.
        case none
        /// Only the third number moved — a fix. Mentioned when asked, never announced.
        case patch
        /// The major or the minor number moved. This is what the dot on the gear is for.
        case big
    }

    public struct Release: Equatable, Sendable {
        /// The release's version without the leading `v` ("0.2.0-mac1").
        public var version: String
        /// The release's title on GitHub, if it has one.
        public var name: String
        /// The page to open in a browser.
        public var url: String

        public init(version: String, name: String = "", url: String = UpdateCheck.pageURL) {
            self.version = version; self.name = name; self.url = url
        }
    }

    public enum Failure: Equatable, Sendable {
        /// The address is rate-limited (HTTP 403 / 429).
        case rateLimited
        /// No network, a timeout, a proxy, a server error.
        case unreachable
        /// GitHub answered, but not with a release we can read.
        case unexpectedAnswer
    }

    /// What one check came to. The UI localizes it.
    public enum Outcome: Equatable, Sendable {
        case upToDate(latest: Release)
        case newer(Release, step: Step)
        /// The fork has published nothing yet (HTTP 404).
        case noReleases
        case failed(Failure)
    }

    // MARK: comparison

    /// How the release `found` compares with the one we are. Numbers, not text: the day 1.10
    /// comes out, a string comparison would file it before 1.9 and the update would never be
    /// offered. Anything unreadable — "dev" included — is `.none`: silence is the only safe
    /// answer to a reply we do not understand.
    public static func compare(current: String, found: String) -> Step {
        guard let a = parse(current), let b = parse(found) else { return .none }
        for i in 0..<4 where a[i] != b[i] {
            if b[i] < a[i] { return .none }
            return i < 2 ? .big : .patch
        }
        return .none
    }

    /// Four numbers out of "v0.2.0", "0.2.0-mac1" or "1.1.0.0"; nil if it is not a version at all.
    /// A pre-release / build suffix after `-` or `+` is ignored (so `0.2.0-mac1` is 0.2.0); the
    /// missing tail is zeroes, so 1.1 and 1.1.0.0 are one and the same.
    public static func parse(_ text: String) -> [Int]? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = String(s[..<cut]) }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 4 else { return nil }
        var n = [0, 0, 0, 0]
        for (i, part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(part) else { return nil }
            n[i] = v
        }
        return n
    }

    // MARK: answer

    private struct Payload: Decodable {
        var tag_name: String?
        var name: String?
        var html_url: String?
    }

    /// Reads GitHub's answer. Total: every status and every body ends up as an `Outcome`.
    public static func outcome(status: Int, body: Data, current: String) -> Outcome {
        switch status {
        case 200: break
        case 404: return .noReleases
        case 403, 429: return .failed(.rateLimited)
        default: return .failed(.unreachable)
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: body),
              var tag = p.tag_name?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty
        else { return .failed(.unexpectedAnswer) }
        if let first = tag.first, first == "v" || first == "V" { tag.removeFirst() }
        guard !tag.isEmpty else { return .failed(.unexpectedAnswer) }

        let release = Release(version: tag, name: p.name ?? "",
                              url: safePage(p.html_url) ?? pageURL)
        let step = compare(current: current, found: tag)
        return step == .none ? .upToDate(latest: release) : .newer(release, step: step)
    }

    /// Only an https link to github.com is ever offered to be opened.
    static func safePage(_ url: String?) -> String? {
        guard let url, let u = URL(string: url), u.scheme == "https",
              let host = u.host?.lowercased(), host == "github.com" || host.hasSuffix(".github.com")
        else { return nil }
        return url
    }

    // MARK: fetch

    /// Ask, once. Never throws: every way this can fail ends up in the outcome.
    public static func fetch(current: String, using fetcher: UpdateFetching = URLSessionFetcher()) async -> Outcome {
        guard let url = URL(string: latestURL) else { return .failed(.unexpectedAnswer) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        // GitHub refuses a request without a User-Agent, and an honest name is better than a
        // borrowed browser's.
        req.setValue("AliveForMac/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, status) = try await fetcher.get(req)
            return outcome(status: status, body: data, current: current)
        } catch {
            return .failed(.unreachable)
        }
    }
}

/// The one seam to the network: tests hand in a stub, the app the real session.
public protocol UpdateFetching: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionFetcher: UpdateFetching {
    public init() {}

    public func get(_ request: URLRequest) async throws -> (Data, Int) {
        // Ephemeral: no cookies, no credentials, no cache kept on disk.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
