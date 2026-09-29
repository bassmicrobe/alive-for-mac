// Port of the plugins mode of src/MainForm.cs: summary cards on top, the plugin list, and the
// inspector on the right (DetailPanel). Search is the toolbar's (`app.searchText`), filters are the
// toolbar's Filters button (`PluginFiltersSheet`).
import SwiftUI

struct PluginsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                PluginSummaryBar()
                PluginListView()
            }
            PluginDetailPanel()
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, Theme.pad)
    }
}
