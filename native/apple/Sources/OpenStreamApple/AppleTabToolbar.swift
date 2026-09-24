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
        ForEach(AppleTabToolbarPolicy.items(for: tab), id: \.self) { item in
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

    private static var placement: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .primaryAction
        #endif
    }
}
#endif
