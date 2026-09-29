// Mac-only: About page — credits, links, unofficial-port disclaimer, trademark note and the two
// license texts (upstream's verbatim + the port's), read from bundle resources.
import SwiftUI
import AppKit

struct AboutView: View {
    private static let upstreamURL = URL(string: "https://github.com/rueblose/alive")!
    private static let portURL = URL(string: "https://github.com/bassmicrobe/alive-for-mac")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Text(SettingsStrings.credit.s).font(Theme.fBody).foregroundStyle(Theme.text)
                HStack(spacing: 18) {
                    Link(SettingsStrings.linkUpstream.s, destination: Self.upstreamURL)
                    Link(SettingsStrings.linkPort.s, destination: Self.portURL)
                }
                .font(Theme.fBody)
                notes
                licenses
            }
            .padding(Theme.pad)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text(CommonStrings.appName.s).font(Theme.fHead).foregroundStyle(Theme.text)
            Text(SettingsStrings.version.f(AboutInfo.version))
                .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
            Text(SettingsStrings.upstreamCommit.f(AboutInfo.upstreamCommit))
                .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingsStrings.disclaimer.s)
            Text(SettingsStrings.trademarks.s).foregroundStyle(Theme.secondaryText)
        }
        .font(Theme.fSmall)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var licenses: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(SettingsStrings.licenses.s)
            LicenseBox(title: SettingsStrings.licenseUpstream.s, resource: "LICENSE")
            LicenseBox(title: SettingsStrings.licenseMac.s, resource: "LICENSE-macos")
        }
    }
}

/// Values read from the bundle's Info.plist (written by scripts/build-app.sh).
enum AboutInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? SettingsStrings.versionDev.s
    }

    /// Short SHA of the upstream commit this build is based on.
    static var upstreamCommit: String {
        guard let sha = Bundle.main.object(forInfoDictionaryKey: "AliveUpstreamCommit") as? String,
              !sha.isEmpty else { return SettingsStrings.unknown.s }
        return String(sha.prefix(7))
    }
}

private struct LicenseBox: View {
    let title: String
    let resource: String

    var body: some View {
        DisclosureGroup(title) {
            ScrollView {
                Text(licenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.thumbR + 2, style: .continuous))
        }
        .font(Theme.fBody)
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return SettingsStrings.licenseMissing.s
        }
        return text
    }
}
