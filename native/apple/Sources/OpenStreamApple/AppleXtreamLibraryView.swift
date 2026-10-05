import SwiftUI

struct AppleXtreamLibrarySections: View {
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    @State private var library = AppleXtreamLibraryStore.shared
    var body: some View {
        if !library.continueWatching.isEmpty {
            AppleMediaShelf(title: "Continue Watching") {
                ForEach(library.continueWatching) { item in
                    AppleXtreamTitleLink(item: item, sourceStore: sourceStore, mediaIndex: mediaIndex,
                        settings: settings, openSettings: openSettings, showsProgress: true)
                }
            }
        }
        ForEach(library.failures.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
            if let message = library.failures[id] {
                Label(message, systemImage: "exclamationmark.triangle").padding(.horizontal, 16)
                    .accessibilityIdentifier("library.xtream.failure")
            }
        }
        ForEach(library.shelves.filter { !$0.preview.isEmpty }) { shelf in
            AppleMediaShelf(title: shelf.title) {
                ForEach(shelf.preview) { item in
                    AppleXtreamTitleLink(item: item, sourceStore: sourceStore, mediaIndex: mediaIndex,
                        settings: settings, openSettings: openSettings)
                }
                NavigationLink {
                    AppleXtreamCategoryView(shelf: shelf, sourceStore: sourceStore, mediaIndex: mediaIndex,
                        settings: settings, openSettings: openSettings)
                } label: { Text("See All").frame(minWidth: 120, minHeight: 60) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.xtream.category.\(shelf.id)")
            }
        }
        if library.isLoading { ProgressView().accessibilityLabel("Loading your provider’s movies and series") }
    }
}

struct AppleXtreamTitleLink: View {
    let item: AppleCatalogItem
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    var showsProgress = false
    @Environment(\.appleTabToolbar) private var tabToolbar
    var body: some View {
        if let reference = AppleXtreamReference.parse(item.mediaID), let source = AppleXtreamLibraryStore.shared.source(reference) {
            NavigationLink {
                AppleCatalogItemDetailView(item: item, source: source, mediaIndex: mediaIndex,
                    playbackSources: sourceStore.sources, metadataConfiguration: settings.tmdbConfiguration,
                    gatewayConfig: nil, playbackResolver: AppleStremioPlaybackResolver(), settings: settings,
                    openSettings: openSettings, tabToolbar: tabToolbar)
            } label: {
                AppleCatalogCard(item: item, progress: progress)
            }
            .appleCatalogCardButtonStyle()
            .accessibilityIdentifier("library.xtream.title.\(item.name)")
        }
    }
    private var progress: Double? {
        guard showsProgress, let reference = AppleXtreamReference.parse(item.mediaID), let saved = ApplePlaybackStore().progress(for: AppleMediaIngestion.catalogRecord(instanceID:
            reference.sourceID, item: item).id) else { return nil }
        return AppleWatchProgress.fraction(position: saved.position, duration: saved.duration)
    }
}

struct AppleXtreamCategoryView: View {
    let shelf: AppleXtreamLibraryStore.Shelf
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    @State private var limit = AppleXtreamLibraryPolicy.pageSize
    @ScaledMetric(relativeTo: .body) private var columnWidth = 150.0

    private var columns: [GridItem] {
        #if os(tvOS)
        // A standard TV poster is 230 points wide; leave room for its focus lift.
        [GridItem(.adaptive(minimum: 260, maximum: 300))]
        #else
        let minimum = min(max(columnWidth, 150), 260)
        return [GridItem(.adaptive(minimum: minimum, maximum: max(220, minimum)))]
        #endif
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(shelf.references.prefix(limit)), id: \.self) { reference in
                    if let item = AppleXtreamLibraryStore.shared.catalog(reference) {
                        AppleXtreamTitleLink(item: item, sourceStore: sourceStore, mediaIndex: mediaIndex,
                            settings: settings, openSettings: openSettings)
                    }
                }
            }.padding()
            if limit < shelf.references.count {
                Button("Show More", action: showMore).padding()
                    .accessibilityIdentifier("library.xtream.more")
            }
        }
        .scrollIndicators(AppleDesignTokens.scrollIndicatorVisibility)
        .navigationTitle(shelf.title)
        .task(id: shelf.id) { AppleXtreamLibraryStore.shared.refreshProgress() }
    }
    private func showMore() { limit = min(limit + AppleXtreamLibraryPolicy.pageSize, shelf.references.count) }
}
