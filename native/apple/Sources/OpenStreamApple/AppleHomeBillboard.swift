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
/// This view supplies the inline trailer stage and the shared title-page
/// primary action, so every hero layout agrees on what its button will do.
/// The Apple TV's stage is the still alone: it plays no trailer and looks
/// none up (`AppleTitlePagePolicy.offersTrailers`).
/// A stacked card lived here between 2026-09-18
/// and 2026-09-20 and was the iPad landscape regression the owner reported: the
/// art was capped at a flat 600 pt, the wordmark sat below it at a flat 90 pt,
/// and Play/Details were pushed off the bottom of the screen.
struct AppleHomeBillboard<Actions: View>: View {
    let item: AppleCatalogItem
    let sources: [AppleSource]
    let progressID: String
    let preferredSourceID: AppleSource.ID
    let onPlay: () -> Void
    /// Opens the title page: the button's action when nothing here plays.
    let onOpenDetails: () -> Void
    let settings: AppleSettingsStore
    let viewportSize: CGSize
    let wordmark: URL?
    let rotationCount: Int
    let rotationIndex: Int
    /// Set on an iPhone in portrait: draw the Apple TV app's hero
    /// (`AppleHomePhoneHero`) over the same stage instead of the featured one.
    var phone: Phone? = nil
    /// Set on the Mac: draw the Apple TV app's Mac hero (`AppleHomeMacHero`)
    /// over the same stage.
    var mac: Mac? = nil
    /// Set on the Apple TV's Discover: the Apple TV app's hero details over
    /// the billboard (badge, kind line and rating, cycle-driven dots).
    var tv: TV? = nil
    @ViewBuilder var actions: (AppleTitlePagePolicy.HeroButton, @escaping () -> Void) -> Actions
    @State private var episodes: [AppleStremioEpisode] = []
    /// Every lookup that can find a trailer has answered.
    @State private var actionMetadataLoaded = false
    /// A trailer's video — pressed or autoplaying — is on screen; a press
    /// would only cut it back to the art and restart it. A press while one
    /// is still loading behind the art starts the load again, so a stalled
    /// trailer never leaves a dead button.
    @State private var trailerIsOnScreen = false
    @Environment(\.appleTMDBConfiguration) private var metadataConfiguration
    @State private var previewTrailerKeys: [String] = []
    @State private var detailTrailerKeys: [String] = []
    @State private var trailerRequest: UUID?
    @State private var downloadCoordinator = AppleOfflineDownloadCoordinator()

    private var selectedEpisode: AppleStremioEpisode? {
        let store = ApplePlaybackStore()
        let progress = ApplePlaybackProgressFeed.shared.progress(for: progressID, in: store)
        let completedIDs = store.completedMediaIDs(among: episodes.map(\.id))
        return AppleTitlePagePolicy.heroEpisode(
            item: item, progress: progress, episodes: episodes, completedIDs: completedIDs,
            localResumeEpisode: AppleLocalLibraryStore.shared.resumeEpisode(for: item, group: nil, episodes: episodes)
        )
    }

    private var hasPlaybackRoute: Bool {
        AppleTitlePagePolicy.heroHasPlaybackRoute(
            item: item, sources: sources,
            hasCompletedDownload: downloadCoordinator.state.isCompleted
        )
    }

    /// The Apple TV hero never offers a trailer (N23 removes them there).
    private var trailerAvailability: AppleTitlePagePolicy.TrailerAvailability {
        #if os(tvOS)
        .none
        #else
        trailerKey != nil ? .available : (actionMetadataLoaded ? .none : .pending)
        #endif
    }

    private var primaryAction: AppleTitlePagePolicy.PrimaryAction? {
        AppleTitlePagePolicy.heroPrimaryAction(
            type: item.type, progress: ApplePlaybackProgressFeed.shared.progress(for: progressID),
            selectedEpisode: selectedEpisode, isPlayable: hasPlaybackRoute, trailer: trailerAvailability
        )
    }

    private var actionButtons: Actions {
        actions(AppleTitlePagePolicy.HeroButton(action: primaryAction,
                                                isDownloaded: downloadCoordinator.state.isCompleted),
                performPrimaryAction)
    }

    private func performPrimaryAction() {
        switch primaryAction {
        case .playTrailer:
            // Art-first: the art stays and the button keeps its label; the
            // video fades in over it once it plays, or never, silently.
            guard !trailerIsOnScreen else { return }
            trailerRequest = UUID()
        case .details:
            onOpenDetails()
        case .play, .playEpisode, .resume:
            onPlay()
        case nil:
            break
        }
    }

    private var trailerKey: String? {
        (detailTrailerKeys + previewTrailerKeys).first { AppleTrailerPreviewPolicy.embedURL(for: $0) != nil }
    }

    /// Use the title page's metadata clients and canonical-id resolution too:
    /// a catalog's private id may need resolving before it can list episodes.
    private func loadActionMetadata() async {
        episodes = []
        actionMetadataLoaded = false
        previewTrailerKeys = []
        detailTrailerKeys = []
        trailerRequest = nil
        trailerIsOnScreen = false
        let client = AppleStremioMetadataClient()
        let resolver = AppleMetadataResolver()
        let sources = sources
        let preferred = preferredSourceID
        let item = item
        let configuration = metadataConfiguration
        func addLookups(to group: inout TaskGroup<AppleHeroMetadataOutcome>, mediaID: String) {
            if item.type == "series" {
                group.addTask {
                    .episodes((try? await client.episodes(sources: sources, preferredSourceID: preferred,
                                                          mediaID: mediaID)) ?? [])
                }
            }
            // The details and preview lookups only feed the trailer key, so
            // the Apple TV, which plays no trailer, skips them.
            guard AppleTitlePagePolicy.offersTrailers() else { return }
            group.addTask {
                .details(try? await resolver.resolve(sources: sources, preferredSourceID: preferred,
                    type: item.type, mediaID: mediaID, configuration: configuration))
            }
        }
        await withTaskGroup(of: AppleHeroMetadataOutcome.self) { group in
            if AppleTitlePagePolicy.offersTrailers() {
                group.addTask {
                    .preview(await client.previewAssets(sources: sources, preferredSourceID: preferred,
                                                         type: item.type, mediaID: item.mediaID))
                }
            }
            if let canonicalID = ApplePlayGatingPolicy.canonicalMediaID(item.mediaID) {
                addLookups(to: &group, mediaID: canonicalID)
            } else if AppleMediaServerItemReference.parse(item.mediaID) == nil {
                group.addTask {
                    .identity(await client.imdbIdentifier(sources: sources, preferredSourceID: preferred,
                                                          type: item.type, id: item.mediaID))
                }
            }
            while let outcome = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch outcome {
                case .preview(let assets): previewTrailerKeys = assets?.trailerYouTubeKeys ?? []
                case .details(let details): detailTrailerKeys = details?.trailerYouTubeKeys ?? []
                case .identity(let id): addLookups(to: &group, mediaID: id ?? item.mediaID)
                case .episodes(let loaded):
                    episodes = loaded
                }
            }
        }
        guard !Task.isCancelled else { return }
        actionMetadataLoaded = true
    }

    /// The decoded still, handed to the iPhone hero's trailer so its cover
    /// paints these pixels the moment it is inserted — the title page does the
    /// same. Without it the cover loaded its own copy and the hero went black
    /// for a moment when the trailer started (iPhone sim, 2026-09-22).
    @State private var stillImage: CGImage?
    /// Whose still has loaded or failed; the trailer waits on it.
    @State private var stillOutcome: (itemID: String, art: AppleTrailerArtFirstPolicy.Art)?

    private var stillArt: AppleTrailerArtFirstPolicy.Art {
        stillOutcome?.itemID == item.id ? stillOutcome?.art ?? .loading : .loading
    }

    private func recordStill(_ art: AppleTrailerArtFirstPolicy.Art) {
        let current = stillOutcome?.itemID == item.id ? stillArt : .loading
        stillOutcome = (item.id, current.settling(with: art))
    }

    struct Phone {
        let artHeight: CGFloat
        let copyFadeLine: CGFloat
        let badge: AppleHeroBadge?
    }

    struct Mac {
        let layout: AppleMacHeroLayout
    }

    struct TV {
        let badge: AppleHeroBadge?
        let cycle: AppleHeroRotation.Cycle
    }

    var body: some View {
        heroBody
            .task(id: "\(item.id):\(catalogConfigurationIdentity(sources))") { await loadActionMetadata() }
            // A pressed trailer holds the hero's page while it loads behind
            // the art; one that never plays lets go after 30 s, silently, and
            // the art simply stays (art-first, owner 2026-09-24).
            .task(id: trailerRequest) {
                guard trailerRequest != nil else { return }
                try? await Task.sleep(for: .seconds(AppleTrailerArtFirstPolicy.pressedTrailerGiveUp))
                guard !Task.isCancelled, !trailerIsOnScreen else { return }
                trailerRequest = nil
            }
            .task(id: "\(progressID):\(selectedEpisode?.id ?? "")") {
                let offlineID = selectedEpisode.map { "\(progressID):\($0.id)" } ?? progressID
                await downloadCoordinator.loadExisting(mediaID: offlineID, itemTitle: item.name)
            }
    }

    @ViewBuilder private var heroBody: some View {
        #if os(macOS)
        if let mac {
            AppleHomeMacHero(item: item, layout: mac.layout, wordmark: wordmark, stage: stage,
                             onOpenDetails: onOpenDetails) { actionButtons }
        } else {
            standardBody
        }
        #else
        standardBody
        #endif
    }

    @ViewBuilder
    private var standardBody: some View {
        #if os(tvOS)
        if let tv {
            AppleTVBillboard(item: item, wordmark: wordmark, rotationCount: rotationCount,
                             rotationIndex: rotationIndex, stage: stage, badge: tv.badge,
                             usesKindMetadata: true, cycle: tv.cycle) { actionButtons }
        } else {
            featuredBody
        }
        #else
        featuredBody
        #endif
    }

    @ViewBuilder
    private var featuredBody: some View {
        if let phone {
            AppleHomePhoneHero(item: item, artHeight: phone.artHeight, copyFadeLine: phone.copyFadeLine,
                               wordmark: wordmark, badge: phone.badge,
                               stage: stage, onOpenDetails: onOpenDetails) { actionButtons }
        } else {
            AppleFeaturedHero(
                item: item,
                viewportSize: viewportSize,
                wordmark: wordmark,
                rotationCount: rotationCount,
                rotationIndex: rotationIndex,
                stage: stage
            ) { actionButtons }
        }
    }

    private var stage: AnyView {
        AnyView(
            ZStack {
                // The still sits outside the per-title identity below. It
                // was inside it, so every page change remounted it empty
                // and the hero showed a bare surface under the new copy
                // until the backdrop decoded (sim finding c, 2026-09-22).
                // It keeps the old still until the new one lands: across a
                // page change `AppleHeroPageGate` has already warmed it (the
                // iPhone portrait pages are separate views), and a resize
                // must never paint the loading surface over the hero.
                AppleRemoteImage(
                    url: item.backgroundURL ?? item.posterURL,
                    placeholderSystemImage: "",
                    onLoad: { image in
                        stillImage = image
                        recordStill(.loaded)
                        appleTrace("hero still loaded \(item.name) \(image.width)px")
                        AppleLaunchReadiness.shared.markFirstScreenReady()
                    },
                    onFailure: {
                        stillImage = nil
                        recordStill(.failed)
                        appleTrace("hero still failed \(item.name)")
                        AppleLaunchReadiness.shared.markFirstScreenReady()
                    },
                    loadingFill: AppleDesignTokens.surface,
                    keepsImageWhileReloading: true,
                    // The Mac window resizes live; decode the still once.
                    fixedPixelDimension: mac != nil ? AppleMacHeroLayout.stillPixelDimension : nil
                )
                #if !os(tvOS)
                AppleHomeHeroPreview(item: item, sources: sources, settings: settings,
                                     trailerRequest: trailerRequest, requestedTrailerKey: trailerKey,
                                     art: stillArt,
                                     artworkImage: phone != nil || mac != nil ? stillImage : nil,
                                     muteTopInset: mac.map { $0.layout.topInset + AppleMacHeroLayout.muteTopInset },
                                     onTrailerOnScreen: { trailerIsOnScreen = $0 })
                    .id(item.id)
                #endif
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                appleTrace("hero stage \(item.name) \(Int(size.width))x\(Int(size.height))")
            }
        )
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

#if !os(tvOS)
@MainActor
private struct AppleHomeHeroPreview: View {
    let item: AppleCatalogItem
    let sources: [AppleSource]
    let settings: AppleSettingsStore
    var trailerRequest: UUID? = nil
    var requestedTrailerKey: String? = nil
    /// The still under it: the trailer is not asked for until it is up.
    var art: AppleTrailerArtFirstPolicy.Art = .loading
    var artworkImage: CGImage? = nil
    /// The Mac hero's round mute button sits this far from the top of the
    /// art (below the toolbar); nil on every other hero.
    var muteTopInset: CGFloat? = nil
    /// The video came on screen over the art (true) or left it (false).
    var onTrailerOnScreen: (Bool) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isPresented = false
    @State private var embedURL: URL?
    @State private var isPlaying = false
    /// The video is on screen, past the art (`AppleTrailerArtFirstPolicy`).
    @State private var isRevealed = false
    /// The art frame the still fills, which the 16:9 web view overhangs.
    @State private var artFrameSize: CGSize?
    @State private var isMuted = true
    @State private var replayGeneration = 0
    #if os(iOS) || os(visionOS)
    @State private var systemVideoAutoplayEnabled = UIAccessibility.isVideoAutoplayEnabled
    #endif
    #if os(macOS)
    /// False while a pushed page covers Discover (`AppleMacWindowPresence`).
    @State private var isInWindow = false
    #endif

    private var shouldPreview: Bool {
        #if os(macOS)
        let active = isVisible && isPresented && isInWindow && scenePhase == .active
            && AppleTrailerArtFirstPolicy.mayRequestTrailer(art: art, pressed: trailerRequest != nil)
        #else
        let active = isVisible && isPresented && scenePhase == .active
            && AppleTrailerArtFirstPolicy.mayRequestTrailer(art: art, pressed: trailerRequest != nil)
        #endif
        if trailerRequest != nil { return active }
        let autoplay = active && settings.autoPlayTrailer && !reduceMotion
        #if os(iOS) || os(visionOS)
        return autoplay && systemVideoAutoplayEnabled
        #else
        return autoplay
        #endif
    }

    var body: some View {
        ZStack {
            // Holds the art frame so scroll visibility is measured even with
            // no trailer up; the still itself is drawn by `AppleHomeBillboard`.
            Color.clear
            #if os(macOS)
            AppleMacWindowPresence { isInWindow = $0 }
                .accessibilityHidden(true)
            #endif
            #if os(iOS) || os(visionOS)
            if shouldPreview, let embedURL {
                AppleYouTubeAutoPreview(
                    url: embedURL, artworkURL: item.backgroundURL ?? item.posterURL,
                    artworkImage: artworkImage,
                    isLandscape: true, isPlaying: $isPlaying, isMuted: $isMuted,
                    replayGeneration: $replayGeneration, showsReplay: !isPlaying,
                    coverSize: artFrameSize,
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
                // The zero minimums are what make it so: a flexible frame
                // with no minimum takes its child's size as the minimum, so
                // `maxWidth: .infinity` alone still reported 960 pt on a
                // 402 pt iPhone. The still behind it then reloaded at the new
                // size (the grey frame when the trailer started) and the
                // preview fell under half visible, stopped, and restarted
                // every few seconds (traced on the iPhone sim, 2026-09-22).
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                // A failed trailer leaves by crossfading back to the still.
                .transition(.opacity)
            }
            #elseif os(macOS)
            if shouldPreview, let embedURL {
                AppleMacYouTubeHeroPreview(url: embedURL, artworkImage: artworkImage,
                                           isPlaying: isPlaying, isMuted: isMuted, onStateChange: handleState)
                    // Report only the frame offered, never the web view's own
                    // size: a child that widens the stage widens the hero and
                    // reloads the still (the zero-minimum lesson, 2026-09-22).
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                    .transition(.opacity)
                // Nothing is added over the art until the video is up.
                if isPlaying, isRevealed, let muteTopInset {
                    AppleMacHeroMuteButton(isMuted: isMuted) { isMuted.toggle() }
                        .padding(.top, muteTopInset)
                        .padding(.trailing, AppleMacHeroLayout.muteTrailingInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            #endif
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { artFrameSize = $0 }
        .onAppear { isPresented = true }
        .onDisappear { isPresented = false; stop() }
        .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
        .preference(key: AppleHomeHeroTrailerStateKey.self,
                    value: .init(isPlaying: shouldPreview && isPlaying, isMuted: isMuted,
                                 isRequested: trailerRequest != nil))
        .onChange(of: settings.autoMuteTrailer) { _, muted in isMuted = muted }
        #if os(iOS) || os(visionOS)
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
            systemVideoAutoplayEnabled = UIAccessibility.isVideoAutoplayEnabled
        }
        #endif
        // Low priority: the trailer is only ever an extra over the art, and
        // must not compete with the art and metadata still loading.
        .task(id: "\(item.id):\(shouldPreview):\(trailerRequest?.uuidString ?? ""):\(catalogConfigurationIdentity(sources))",
              priority: .low) {
            await startPreview()
        }
    }

    private func startPreview() async {
        stop()
        guard shouldPreview else { return }
        #if os(macOS)
        if trailerRequest == nil {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
        let assets = await AppleStremioMetadataClient().previewAssets(sources: sources, type: item.type, mediaID: item.mediaID)
        guard !Task.isCancelled, shouldPreview,
              let key = trailerRequest != nil ? requestedTrailerKey : assets?.trailerYouTubeKeys.first,
              let url = AppleTrailerPreviewPolicy.embedURL(for: key) else { return }
        // Always starts muted, as it does on the iPhone; the round button
        // top-right turns the sound on (the Mac has no audio session to lose).
        isMuted = trailerRequest == nil
        appleTrace("mac hero trailer start \(item.name)")
        embedURL = url
        isPlaying = true
        #else
        if trailerRequest == nil {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
        let assets = await AppleStremioMetadataClient().previewAssets(sources: sources, type: item.type, mediaID: item.mediaID)
        guard !Task.isCancelled, shouldPreview,
              let key = trailerRequest != nil ? requestedTrailerKey : assets?.trailerYouTubeKeys.first,
              let url = AppleTrailerPreviewPolicy.embedURL(for: key) else { return }
        isMuted = trailerRequest == nil && settings.autoMuteTrailer
        guard ApplePlaybackSessionPolicy.prepareTrailerAudio() else { return }
        appleTrace("hero trailer start \(item.name)")
        embedURL = url
        isPlaying = true
        #endif
    }

    private func stop() {
        isPlaying = false
        if isRevealed { onTrailerOnScreen(false) }
        isRevealed = false
        embedURL = nil
    }

    private func handleState(_ state: String, muted: Bool, errorCode: Int?) {
        isMuted = muted
        if let change = AppleTrailerArtFirstPolicy.videoLayerChange(forPlayerState: state) {
            isRevealed = change == .reveal
            onTrailerOnScreen(isRevealed)
        }
        if AppleTrailerArtFirstPolicy.dropsVideoLayer(forPlayerState: state) {
            // Nothing to say: the art crossfades back over whatever the
            // player showed, and stays.
            withAnimation(.easeInOut(duration: AppleTrailerArtFirstPolicy.crossfadeDuration(reduceMotion: reduceMotion))) {
                stop()
            }
        }
        if state == "ended" || state == "paused" { isPlaying = false }
    }
}
#endif
