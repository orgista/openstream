import SwiftUI

@MainActor
struct AppleDiscoverView: View {
    @State private var loadedCache = false

    let catalogStore: AppleCatalogStore
    let sourceStore: AppleSourceStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    private let playbackResolver: AppleStremioPlaybackResolver

    init(
        catalogStore: AppleCatalogStore,
        sourceStore: AppleSourceStore,
        settings: AppleSettingsStore,
        openSettings: @escaping () -> Void,
        playbackResolver: AppleStremioPlaybackResolver = AppleStremioPlaybackResolver()
    ) {
        self.catalogStore = catalogStore
        self.sourceStore = sourceStore
        self.settings = settings
        self.openSettings = openSettings
        self.playbackResolver = playbackResolver
    }

    private var visibleSections: [AppleCatalogSection] {
        let activeSourceIDs = Set(
            sourceStore.sources
                .filter(\.isEnabled)
                .map(\.id)
        )
        return catalogStore.sections.filter {
            activeSourceIDs.contains($0.sourceID) && !$0.items.isEmpty
        }
    }

    var body: some View {
        Group {
            if visibleSections.isEmpty {
                ContentUnavailableView {
                    Label(
                        sourceStore.sources.isEmpty ? "No Sources Yet" : "Nothing to Show",
                        systemImage: "sparkles"
                    )
                } actions: {
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.brandPrimary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                        ForEach(visibleSections) { section in
                            if let source = sourceStore.sources.first(where: { $0.id == section.sourceID }) {
                                AppleCatalogSectionView(
                                    section: section,
                                    source: source,
                                    playbackSources: sourceStore.sources,
                                    gatewayConfig: gatewayConfig,
                                    playbackResolver: playbackResolver
                                )
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .overlay(alignment: .top) {
            if catalogStore.isLoading {
                ProgressView()
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(catalogStore.isLoading)
            }
        }
        .task(id: sourceStore.sources) {
            if !loadedCache {
                await catalogStore.loadCachedSections(sources: sourceStore.sources)
                loadedCache = true
            }
            await catalogStore.refresh(sources: sourceStore.sources)
        }
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        48
        #else
        30
        #endif
    }

    private var gatewayConfig: AppleTranscodeGatewayConfig? {
        guard settings.gatewayEnabled else { return nil }
        return try? AppleTranscodeGatewayConfig(
            baseURL: settings.gatewayURL,
            sessionToken: settings.gatewayToken,
            isEnabled: true
        )
    }

    private func refresh() {
        Task { @MainActor in
            await catalogStore.refresh(sources: sourceStore.sources, force: true)
        }
    }
}

private struct AppleCatalogSectionView: View {
    let section: AppleCatalogSection
    let source: AppleSource
    let playbackSources: [AppleSource]
    let gatewayConfig: AppleTranscodeGatewayConfig?
    let playbackResolver: AppleStremioPlaybackResolver

    private var title: String {
        let catalogName = section.catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let catalogName, !catalogName.isEmpty { return catalogName }
        return section.sourceName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            AppleCatalogItemDetailView(
                                item: item,
                                source: source,
                                playbackSources: playbackSources,
                                gatewayConfig: gatewayConfig,
                                playbackResolver: playbackResolver
                            )
                        } label: {
                            AppleCatalogCard(item: item)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        28
        #else
        16
        #endif
    }
}

private struct AppleCatalogCard: View {
    let item: AppleCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppleCatalogArtwork(url: item.posterURL)
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(.rect(cornerRadius: cornerRadius))

            Text(item.name)
                .font(.headline)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)

            if let releaseInfo = item.releaseInfo, !releaseInfo.isEmpty {
                Text(releaseInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        230
        #else
        160
        #endif
    }

    private var cardHeight: CGFloat {
        cardWidth * 1.5
    }

    private var cornerRadius: CGFloat {
        #if os(tvOS)
        18
        #else
        12
        #endif
    }
}

private struct AppleCatalogArtwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                ZStack {
                    Color.secondary.opacity(0.14)
                    ProgressView()
                }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.14)
            Image(systemName: "film")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppleCatalogItemDetailView: View {
    private enum PlaybackState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    let item: AppleCatalogItem
    let source: AppleSource
    let playbackSources: [AppleSource]
    let gatewayConfig: AppleTranscodeGatewayConfig?
    let playbackResolver: AppleStremioPlaybackResolver

    @State private var playbackState = PlaybackState.idle
    @State private var playRequest: UUID?
    @State private var playerPresentation: AppleStremioPlayerPresentation?
    @State private var episodes: [AppleStremioEpisode] = []
    @State private var selectedEpisodeID: String?
    @State private var isLoadingEpisodes = false
    // The item's canonical IMDB id, resolved via a meta add-on. Catalog add-ons
    // (RT, Streaming Catalogs) key items by non-IMDB ids that stream add-ons
    // can't resolve; this is the id actually used for episode + stream lookups.
    @State private var resolvedMediaID: String?

    private let metadataClient = AppleStremioMetadataClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Full-bleed hero. A Color.clear layer defines the size (screen
                // width × heroHeight) and the artwork is a clipped overlay, so
                // the image's scaledToFill can't report an oversized ideal width
                // that widens the vertical ScrollView and shifts the whole
                // content column left ("opens oddly / went sideways").
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .overlay {
                        AppleCatalogArtwork(url: item.backgroundURL ?? item.posterURL)
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    Text(item.name)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        playRequest = UUID()
                    } label: {
                        if playbackState == .loading {
                            ProgressView()
                                .accessibilityLabel("Loading stream")
                        } else {
                            Label("Play", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.brandPrimary)
                    .disabled(playbackState == .loading)

                    if item.type == "series" {
                        if isLoadingEpisodes {
                            ProgressView()
                        } else if !episodes.isEmpty {
                            Picker("Episode", selection: $selectedEpisodeID) {
                                ForEach(episodes) { episode in
                                    Text(episode.displayTitle).tag(Optional(episode.id))
                                }
                            }
                        }
                    }

                    if case .failed(let message) = playbackState {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if let releaseInfo = item.releaseInfo, !releaseInfo.isEmpty {
                            Text(releaseInfo)
                        }
                        if let rating = item.rating {
                            Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                        }
                    }
                    .foregroundStyle(.secondary)

                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .navigationTitle(item.name)
        #if os(iOS)
        // The in-body largeTitle below the artwork IS the visual title; keep the
        // nav-bar copy inline so it doesn't render a second large title over
        // the hero art (the "Man of Steel / of Steel" doubling).
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: playRequest) {
            guard playRequest != nil else { return }
            await resolvePlayback()
        }
        .task(id: item.id) { await prepare() }
        .modifier(AppleStremioPlayerPresentationModifier(presentation: $playerPresentation))
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
        460
        #else
        320
        #endif
    }

    private func resolvePlayback() async {
        playbackState = .loading
        do {
            // Series: play the selected episode id (already IMDB-shaped from the
            // resolved series meta). Movie: play the resolved IMDB id, falling
            // back to the raw catalog id only if meta resolution found nothing.
            let streamID = selectedEpisodeID ?? resolvedMediaID ?? item.mediaID
            let selectedItem = item.withMediaID(streamID)
            let resolved = try await playbackResolver.resolve(
                sources: playbackSources,
                preferredSourceID: source.id,
                item: selectedItem,
                gatewayConfig: gatewayConfig
            )
            try Task.checkCancellation()
            playbackState = .idle
            playerPresentation = AppleStremioPlayerPresentation(
                title: item.name,
                mediaID: selectedItem.id,
                playback: resolved.preparedPlayback
            )
        } catch is CancellationError {
            playbackState = .idle
        } catch {
            playbackState = .failed(error.localizedDescription)
        }
    }

    /// Resolve the item to its IMDB id, then (for series) load episodes keyed
    /// by that id so both metadata and streams resolve against a stream-add-on
    /// friendly identifier.
    private func prepare() async {
        let resolved = await metadataClient.imdbIdentifier(
            sources: playbackSources,
            preferredSourceID: source.id,
            type: item.type,
            id: item.mediaID
        )
        resolvedMediaID = resolved ?? item.mediaID
        guard item.type == "series" else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            episodes = try await metadataClient.episodes(
                sources: playbackSources,
                preferredSourceID: source.id,
                mediaID: resolvedMediaID ?? item.mediaID
            )
            selectedEpisodeID = episodes.first?.id
        } catch is CancellationError {
            return
        } catch {
            episodes = []
            selectedEpisodeID = nil
        }
    }
}

struct AppleStremioPlayerPresentationModifier: ViewModifier {
    @Binding var presentation: AppleStremioPlayerPresentation?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(item: $presentation) { AppleStremioPlayerView(presentation: $0) }
        #else
        content.fullScreenCover(item: $presentation) { AppleStremioPlayerView(presentation: $0) }
        #endif
    }
}
