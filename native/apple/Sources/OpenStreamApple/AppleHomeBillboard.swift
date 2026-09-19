import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
import Combine
#endif

/// Artwork and inline previews share one large stage; copy never obscures it.
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
        VStack(alignment: .leading, spacing: 16) {
            AppleHomeHeroPreview(item: item, sources: sources, settings: settings)
                .id(item.id)
                .frame(height: artworkHeight)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 12) {
                if let wordmark {
                    AppleTrimmedTitleLogo(url: wordmark, alignment: .leading) { _ in }
                        .frame(maxWidth: 300, maxHeight: 90, alignment: .leading)
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
            .padding(.horizontal, copyInset)
            if rotationCount > 1 {
                AppleHomeHeroPageIndicator(count: rotationCount, index: rotationIndex)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var artworkHeight: CGFloat {
        #if os(tvOS)
        620
        #else
        let width = max(viewportSize.width - 32, 320)
        return min(600, max(240, width * 9 / 16))
        #endif
    }

    private var copyInset: CGFloat {
        #if os(tvOS)
        AppleTVChromeMetrics.horizontalSafeInset
        #else
        4
        #endif
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
            AppleCatalogArtwork(url: item.backgroundURL ?? item.posterURL)
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
                AppleTVTrailerPlayerView(source: nativeSource, isMuted: isMuted)
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
