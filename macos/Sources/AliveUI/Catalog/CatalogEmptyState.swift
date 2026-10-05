// Mac-only: an enabled project root can be empty or unreadable. Home and Sets show the same
// scan state and recovery actions, instead of treating an inaccessible folder as an empty library.
import SwiftUI

struct CatalogEmptyState: View {
    @Environment(AppModel.self) private var app

    private var loading: Bool { !app.catalog.isLoaded || app.catalog.isScanning }
    private var failedRoots: [String] { app.catalog.lastScanStats?.failedRoots ?? [] }
    private var unreadableFolders: Int { app.catalog.lastScanStats?.unreadableFolders ?? 0 }
    private var readFailed: Bool { !failedRoots.isEmpty || unreadableFolders > 0 }

    var body: some View {
        VStack(spacing: 16) {
            if loading {
                ProgressView().controlSize(.small)
                Text(CommonStrings.scanning.s).font(Theme.fHead).foregroundStyle(Theme.text)
            } else {
                IconView(icon: .folder, size: 30, weight: .light).foregroundStyle(Theme.secondaryText)
                Text(readFailed ? CommonStrings.catalogReadFailedTitle.s : CommonStrings.noSetsTitle.s)
                    .font(Theme.fHead).foregroundStyle(Theme.text)
                Text(readFailed ? CommonStrings.catalogReadFailedBody.s : CommonStrings.noSetsBody.s)
                    .font(Theme.fBody).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                if !failedRoots.isEmpty {
                    Text(failedRoots.map(SetFormat.homeAbbreviated).joined(separator: "\n"))
                        .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                        .lineLimit(3).truncationMode(.middle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                        .help(failedRoots.joined(separator: "\n"))
                        .accessibilityLabel(failedRoots.joined(separator: "\n"))
                } else if unreadableFolders > 0 {
                    Text(CommonStrings.catalogUnreadableFolders.f(unreadableFolders))
                        .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
                }
            }
            HStack(spacing: 10) {
                PillButton(title: CommonStrings.scanFolders.s, icon: .folder, kind: .primary) {
                    app.presentScanFolders()
                }
                PillButton(title: CommonStrings.rescan.s, icon: .refresh) { app.rescan() }
                    .disabled(loading)
            }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
