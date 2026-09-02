import SwiftUI

enum OpenStreamTab: String, CaseIterable, Identifiable {
    case discover
    case library
    case live
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .library: "Library"
        case .live: "Live"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles"
        case .library: "books.vertical"
        case .live: "dot.radiowaves.left.and.right"
        case .settings: "gearshape"
        }
    }
}

/// Native Apple app shell with one independent navigation stack per tab.
@MainActor
public struct OpenStreamRootView: View {
    @State private var selectedTab = OpenStreamTab.discover
    @State private var sourceStore = AppleSourceStore()
    @State private var catalogStore = AppleCatalogStore()
    @State private var settingsStore = AppleSettingsStore()

    private let webManagement: any AppleWebManagementServing

    public init(webManagement: (any AppleWebManagementServing)? = nil) {
        self.webManagement = webManagement ?? AppleWebManagementController()
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(OpenStreamTab.allCases) { tab in
                NavigationStack {
                    content(for: tab)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    @ViewBuilder
    private func content(for tab: OpenStreamTab) -> some View {
        switch tab {
        case .discover:
            AppleDiscoverView(
                catalogStore: catalogStore,
                sourceStore: sourceStore,
                settings: settingsStore,
                openSettings: { selectedTab = .settings }
            )
            .navigationTitle(tab.title)
        case .library:
            AppleLibraryView(
                sourceStore: sourceStore,
                openSettings: { selectedTab = .settings }
            )
            .navigationTitle(tab.title)
        case .live:
            AppleLiveTVView(
                sourceStore: sourceStore,
                settings: settingsStore,
                openSettings: { selectedTab = .settings }
            )
            .navigationTitle(tab.title)
        case .settings:
            AppleSettingsView(
                settings: settingsStore,
                sourceStore: sourceStore,
                webManagement: webManagement
            )
        }
    }
}

private struct AppleCatalogEmptyView: View {
    let title: String
    let systemImage: String
    let openSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } actions: {
            Button("Open Settings", action: openSettings)
                .buttonStyle(.brandPrimary)
        }
    }
}

public struct OpenStreamThreeBarMark: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let stroke = max(3, geometry.size.height * 0.18)
            VStack(spacing: geometry.size.height * 0.12) {
                bar(width: 0.72, stroke: stroke)
                bar(width: 1, stroke: stroke)
                bar(width: 0.72, stroke: stroke)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, stroke: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: stroke)
            .scaleEffect(x: width, y: 1)
    }
}
