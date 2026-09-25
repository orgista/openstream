#if !os(tvOS)
import SwiftUI

/// Search then Refresh, as `AppleTabToolbarPolicy` lists them for a tab: one
/// set of controls, so Discover's and Library's toolbars cannot drift apart.
struct AppleTabToolbar: ToolbarContent {
    let tab: OpenStreamTab
    /// The spinner takes the glyph's place while the tab reloads. Dimming was
    /// the only answer the button gave, and against cached content that is
    /// over in a frame (button crawl, 2026-09-19).
    let isRefreshing: Bool
    let onSearch: () -> Void
    let onRefresh: () -> Void

    var body: some ToolbarContent {
        // Refresh is a new item when it starts or stops: the Mac toolbar
        // caches an item's view by identity, so on a pushed page (a title
        // page, N37) the spinner it was first given never went away.
        ForEach(AppleTabToolbarPolicy.items(for: tab).map { Slot(item: $0, isRefreshing: $0 == .refresh && isRefreshing) }) { slot in
            let item = slot.item
            ToolbarItem(placement: Self.placement) {
                switch item {
                case .search:
                    Button(action: onSearch) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                    .appleVisionActionTarget()
                case .refresh:
                    Button(action: onRefresh) {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh")
                    .appleVisionActionTarget()
                    .disabled(isRefreshing)
                }
            }
        }
    }

    private struct Slot: Identifiable {
        let item: AppleTabToolbarPolicy.Item
        let isRefreshing: Bool
        var id: String { "\(item.rawValue)\(isRefreshing ? ".busy" : "")" }
    }

    private static var placement: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .primaryAction
        #endif
    }
}
#endif
