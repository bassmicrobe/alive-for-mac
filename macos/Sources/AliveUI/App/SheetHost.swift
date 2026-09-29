// Mac-only: every sheet the main window can present, with plain payloads.
import SwiftUI

enum RootsKind: String, Hashable {
    case projects, samples
}

enum AppSheet: Identifiable, Hashable {
    case filters
    case pluginFilters
    case tags(path: String)
    case roots(RootsKind)
    case preview(path: String)
    case rescue(path: String)
    case export(path: String)
    case help

    var id: String {
        switch self {
        case .filters: return "filters"
        case .pluginFilters: return "pluginFilters"
        case .tags(let path): return "tags:\(path)"
        case .roots(let kind): return "roots:\(kind.rawValue)"
        case .preview(let path): return "preview:\(path)"
        case .rescue(let path): return "rescue:\(path)"
        case .export(let path): return "export:\(path)"
        case .help: return "help"
        }
    }
}

/// Switches to the owning feature's sheet view.
struct SheetHost: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .filters: FiltersSheet()
        case .pluginFilters: PluginFiltersSheet()
        case .tags(let path): TagsSheet(path: path)
        case .roots(let kind): RootsSheet(kind: kind)
        case .preview(let path): PreviewSheet(path: path)
        case .rescue(let path): RescueSheet(path: path)
        case .export(let path): ExportSheet(path: path)
        case .help: HelpSheet()
        }
    }
}
