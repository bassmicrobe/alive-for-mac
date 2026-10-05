// Mac-only: persistent scan feedback while a readable or previously scanned catalog is still
// visible. An unavailable project root must not make old entries appear freshly verified.
import SwiftUI

struct CatalogReadNotice: View {
    let retainedPreviousCatalog: Bool
    let failedRoots: [String]
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            IconView(icon: .warning, size: 13).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            Text(retainedPreviousCatalog ? CommonStrings.catalogRetainedNotice.s : CommonStrings.catalogPartialNotice.s)
                .font(Theme.fBody).foregroundStyle(Theme.text)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(failedRoots.joined(separator: "\n"))
            PillButton(title: CommonStrings.scanFolders.s, icon: .folder) { app.presentScanFolders() }
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
            .strokeBorder(Theme.cardBorder, lineWidth: 1))
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }
}
