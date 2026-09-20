import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
import Combine
#endif

/// Artwork and inline previews share one large stage; copy never obscures it.
///
/// tvOS does not get this card layout. The Apple TV home hero is
/// `AppleTVBillboard` — full-bleed 1920 x 980 art, the app's one fade, copy
/// anchored bottom-leading over the art, the first row peeking in underneath.
/// This view only supplies the preview stage that plays inside it, so Discover
/// keeps its inline trailer without losing the billboard the owner signed off.
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
        #if os(tvOS)
        AppleTVBillboard(
            item: item,
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
        #else
        card
        #endif
    }

    #if !os(tvOS)
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppleHomeHeroPreview(item: item, sources: sources, settings: settings)
                .id(item.id)
                .frame(height: artworkHeight)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 12) {
                if let wordmark {
                    // A definite height, not `maxHeight`: the wordmark is drawn
                    // inside a GeometryReader, and in a scroll view an upper
                    // bound leaves the height proposal unresolved, which
                    // collapsed the mark to a few illegible points.
                    AppleTrimmedTitleLogo(url: wordmark, alignment: .leading) { _ in }
                        .frame(maxWidth: 300, alignment: .leading)
                        .frame(height: 90)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text(item.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                }
                actions
            }
            if rotationCount > 1 {
                AppleHomeHeroPageIndicator(count: rotationCount, index: rotationIndex)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
    }

    private var artworkHeight: CGFloat {
        let width = max(viewportSize.width - 32, 320)
        return min(600, max(240, width * 9 / 16))
    }
    #endif
}

/// Promotional posters carry their own title treatment and badges in the art.
struct ApplePortraitPromoCard: View {
    let item: AppleCatalogItem
    let viewportWidth: CGFloat

    var body: some View {
        AppleCatalogCard(item: item, sizing: .portraitPromo, viewportWidth: viewportWidth)
    }
}

private struct AppleHomeHeroPageIndicator: View {
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
