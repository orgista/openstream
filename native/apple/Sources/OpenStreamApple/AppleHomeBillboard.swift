import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
import Combine
#endif

/// Discover's home hero. Every platform draws the same composition —
/// `AppleFeaturedHero`: art edge to edge, the app's one fade, the wordmark
/// lockup with genre/year, a two-line synopsis, Play and Details, and the
/// rotation dots, all anchored bottom-leading over the art, with the first row
/// peeking in underneath.
///
/// This view's only job is to hand that hero a *stage* — the inline trailer
/// preview that can take the still's place — so Discover keeps its preview
/// without owning a second layout. A stacked card lived here between 2026-09-18
/// and 2026-09-20 and was the iPad landscape regression the owner reported: the
/// art was capped at a flat 600 pt, the wordmark sat below it at a flat 90 pt,
/// and Play/Details were pushed off the bottom of the screen.
struct AppleHomeBillboard<Actions: View>: View {
    let item: AppleCatalogItem
    let sources: [AppleSource]
    let settings: AppleSettingsStore
    let viewportSize: CGSize
    let wordmark: URL?
    let rotationCount: Int
    let rotationIndex: Int
    @ViewBuilder var actions: Actions

    var body: some View {
        AppleFeaturedHero(
            item: item,
            viewportSize: viewportSize,
            wordmark: wordmark,
            rotationCount: rotationCount,
            rotationIndex: rotationIndex,
            stage: AnyView(
                AppleHomeHeroPreview(
                    item: item, sources: sources, settings: settings,
                    loadingFill: AppleDesignTokens.surface
                )
                .id(item.id)
            )
        ) { actions }
    }
}

/// Promotional posters carry their own title treatment and badges in the art.
struct ApplePortraitPromoCard: View {
    let item: AppleCatalogItem
    let viewportWidth: CGFloat

    var body: some View {
        AppleCatalogCard(item: item, sizing: .portraitPromo, viewportWidth: viewportWidth)
    }
}

/// The rotation dots under the hero's buttons. `AppleFeaturedHero` draws it on
/// iPhone, iPad, Mac and Vision Pro; tvOS has its own focus-aware indicator.
struct AppleHomeHeroPageIndicator: View {
    let count: Int
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(.primary.opacity(0.2))
                    .frame(width: position == index ? 28 : 8, height: 4)
                    .overlay(alignment: .leading) {
                        if position == index {
                            Capsule().fill(.primary).frame(width: 28 * fill)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Featured \(index + 1) of \(count)")
        .task(id: "\(index):\(reduceMotion)") {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            let progress = AppleHeroRotation.progress(at: .now)
            withTransaction(transaction) { fill = reduceMotion ? 1 : progress }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: AppleHeroRotation.interval * (1 - progress))) { fill = 1 }
        }
    }
}

@MainActor
private struct AppleHomeHeroPreview: View {
    let item: AppleCatalogItem
    let sources: [AppleSource]
    let settings: AppleSettingsStore
    /// The billboard wants its own ground while the still loads; shelf-sized
    /// callers keep `AppleCatalogArtwork`'s near-invisible default.
    var loadingFill: Color = .white.opacity(0.025)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isPresented = false
    @State private var embedURL: URL?
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var replayGeneration = 0
    #if os(iOS) || os(visionOS)
    @State private var systemVideoAutoplayEnabled = UIAccessibility.isVideoAutoplayEnabled
    #endif
    #if os(tvOS)
    @State private var nativeSource: AppleYouTubeStreamResolver.Source?
    #endif

    private var shouldPreview: Bool {
        let active = isVisible && isPresented && scenePhase == .active && settings.autoPlayTrailer && !reduceMotion
        #if os(iOS) || os(visionOS)
        return active && systemVideoAutoplayEnabled
        #else
        return active
        #endif
    }

    var body: some View {
        ZStack {
            AppleCatalogArtwork(url: item.backgroundURL ?? item.posterURL, loadingFill: loadingFill)
            #if os(iOS) || os(visionOS)
            if shouldPreview, let embedURL {
                AppleYouTubeAutoPreview(
                    url: embedURL, artworkURL: item.backgroundURL ?? item.posterURL,
                    isLandscape: true, isPlaying: $isPlaying, isMuted: $isMuted,
                    replayGeneration: $replayGeneration, showsReplay: !isPlaying,
                    onStateChange: handleState,
                    onTap: { isPlaying.toggle() },
                    onMute: { isMuted.toggle() },
                    onReplay: { replayGeneration &+= 1; isPlaying = true }
                )
                // Cover the art frame instead of fitting inside it. The embed
                // letterboxes the video against its own black ground, so a
                // 2.57:1 hero frame put ~180 pt of black down each side of a
                // 16:9 trailer — the "black bars around the video" the owner
                // reported on the iPad (2026-09-20). Sizing the web view to
                // 16:9 *over* the frame and letting the hero's `clipped()`
                // crop it means the still and the preview fill identically.
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                // …and then report only the space it was offered. A covering
                // child otherwise widens the stage, the stage widens the hero,
                // and the hero's copy column is laid out against a width wider
                // than the screen — which put Details off the right edge of an
                // iPhone and stopped the synopsis wrapping (2026-09-20).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            #elseif os(tvOS)
            if shouldPreview, let nativeSource {
                AppleTVTrailerPlayerView(source: nativeSource, isMuted: isMuted) {
                    // The stream will not play. Drop back to the backdrop
                    // rather than leaving a dead player over the billboard.
                    self.nativeSource = nil
                }
            }
            #endif
        }
        .onAppear { isPresented = true }
        .onDisappear { isPresented = false; stop() }
        .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
        .onChange(of: settings.autoMuteTrailer) { _, muted in isMuted = muted }
        #if os(iOS) || os(visionOS)
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
            systemVideoAutoplayEnabled = UIAccessibility.isVideoAutoplayEnabled
        }
        #endif
        .task(id: "\(item.id):\(shouldPreview):\(catalogConfigurationIdentity(sources))") {
            await startPreview()
        }
    }

    private func startPreview() async {
        stop()
        guard shouldPreview else { return }
        #if os(iOS) || os(tvOS) || os(visionOS)
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        let assets = await AppleStremioMetadataClient().previewAssets(sources: sources, type: item.type, mediaID: item.mediaID)
        guard !Task.isCancelled, shouldPreview,
              let key = assets?.trailerYouTubeKeys.first,
              let url = AppleTrailerPreviewPolicy.embedURL(for: key) else { return }
        isMuted = settings.autoMuteTrailer
        #if os(tvOS)
        guard let stream = try? await AppleYouTubeStreamResolver.shared.resolve(videoID: key),
              !Task.isCancelled, shouldPreview else { return }
        guard ApplePlaybackSessionPolicy.prepareTrailerAudio() else { return }
        nativeSource = stream.source
        #else
        guard ApplePlaybackSessionPolicy.prepareTrailerAudio() else { return }
        embedURL = url
        isPlaying = true
        #endif
        #endif
    }

    private func stop() {
        isPlaying = false
        embedURL = nil
        #if os(tvOS)
        nativeSource = nil
        #endif
    }

    private func handleState(_ state: String, muted: Bool, errorCode: Int?) {
        isMuted = muted
        if state == "error" || state == "autoplay-blocked" { stop() }
        if state == "ended" || state == "paused" { isPlaying = false }
    }
}
