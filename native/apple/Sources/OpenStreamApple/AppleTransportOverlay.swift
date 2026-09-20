import AVFoundation
import SwiftUI

/// Transport controls for decoded video surfaces and the full-screen Live player.
@MainActor
struct AppleTransportOverlay: View {
    struct SharePlayMenu {
        typealias Action = @MainActor () -> Void
        let primaryTitle: String
        let primaryAction: Action
        let secondaryTitle: String?
        let secondaryAction: Action?

        init(primaryTitle: String, primaryAction: @escaping Action, secondaryTitle: String? = nil, secondaryAction: Action? = nil) {
            self.primaryTitle = primaryTitle
            self.primaryAction = primaryAction
            self.secondaryTitle = secondaryTitle
            self.secondaryAction = secondaryAction
        }

        #if !os(macOS)
        @MainActor var uiMenu: UIMenu {
            var actions: [UIMenuElement] = [UIAction(title: primaryTitle) { _ in primaryAction() }]
            if let secondaryTitle, let secondaryAction {
                actions.append(UIAction(title: secondaryTitle, attributes: .destructive) { _ in secondaryAction() })
            }
            return UIMenu(title: "SharePlay", image: UIImage(systemName: "shareplay"), children: actions)
        }
        #endif
    }

    let coordinator: ApplePlaybackCoordinator
    let request: ApplePlaybackRequest
    let otherSources: (() -> Void)?
    let onShowChannels: (() -> Void)?
    /// True while another surface — the live channel panel — is drawn over the
    /// player. `allowsHitTesting(false)` is not enough on its own: the clear
    /// full-screen "Show playback controls" button stays in the accessibility
    /// tree and is then the element found at every point over the panel, so
    /// VoiceOver read the surface instead of the channel rows and XCTest
    /// reported every visible row unhittable. `accessibilityHidden` did not
    /// remove the descendants either; the controls have to leave the
    /// hierarchy (2026-09-19).
    let isObscured: Bool
    let onBackgroundTap: ((_ wasHidden: Bool) -> Void)?
    let onControlsVisibilityChanged: ((Bool) -> Void)?
    let hideChromeSignal: Bool
    let onRequestFullScreen: (() -> Void)?
    let onClose: (() -> Void)?
    let sharePlayMenu: SharePlayMenu?
    @Environment(\.dismiss) private var dismiss

    @State private var model: AppleTransportOverlayModel
    @State private var bottomBarHeight: CGFloat = 0
    @State private var isMuted = false

    /// Task 9: on Apple TV the surface overlay keeps only the scrubber and one
    /// captions control; the remote's buttons carry everything else.
    private let chrome = AppleTVPlaybackPresentationPolicy.surfaceChrome()

    /// The controls this overlay draws, from the same policy. The overlay is
    /// also owns Live chrome, which uses the same controls as the surface route.
    private var controls: [AppleTVPlaybackPresentationPolicy.SurfaceControl] {
        AppleTVPlaybackPresentationPolicy.visibleControls(
            route: .surface,
            isScrubbable: model.isScrubbable,
            hasOtherSources: otherSources != nil,
            hasSharePlay: sharePlayMenu != nil
        )
    }

    #if os(tvOS)
    fileprivate enum TVFocus: Hashable { case surface, scrubber, captions, nextEpisode, skipIntro }
    @FocusState private var tvFocus: TVFocus?
    #endif

    init(
        coordinator: ApplePlaybackCoordinator,
        request: ApplePlaybackRequest,
        otherSources: (() -> Void)? = nil,
        onShowChannels: (() -> Void)? = nil,
        isObscured: Bool = false,
        onBackgroundTap: ((_ wasHidden: Bool) -> Void)? = nil,
        onControlsVisibilityChanged: ((Bool) -> Void)? = nil,
        hideChromeSignal: Bool = false,
        onRequestFullScreen: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        sharePlayMenu: SharePlayMenu? = nil,
        nextEpisode: AppleNextEpisodeContext? = nil
    ) {
        self.coordinator = coordinator
        self.request = request
        self.otherSources = otherSources
        self.onShowChannels = onShowChannels
        self.isObscured = isObscured
        self.onBackgroundTap = onBackgroundTap
        self.onControlsVisibilityChanged = onControlsVisibilityChanged
        self.hideChromeSignal = hideChromeSignal
        self.onRequestFullScreen = onRequestFullScreen
        self.onClose = onClose
        self.sharePlayMenu = sharePlayMenu
        let model = AppleTransportOverlayModel(
            coordinator: coordinator,
            isLive: request.isLive
        )
        if let nextEpisode {
            model.nextEpisode = nextEpisode.start
            model.nextEpisodeTitle = nextEpisode.title
            model.autoPlayNextEpisode = UserDefaults.standard.object(
                forKey: AppleSettingsStore.autoPlayNextEpisodeKey) as? Bool ?? true
        }
        _model = State(initialValue: model)
    }

    #if os(tvOS)
    /// Draws exactly the label and nothing for focus: the playback surface's
    /// focus catcher must never paint over the video.
    private struct AppleTVSurfaceButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
    #endif

    var body: some View {
        ZStack {
            // `isObscured` is always false on tvOS, so the focus catcher below
            // never leaves the hierarchy there and the focus engine keeps its
            // target.
            if !isObscured {
                Button {
                    if chrome.selectTogglesPlayback { 
                        model.togglePlayPause() 
                    } else { 
                        let wasHidden = !model.controlsVisible
                        model.bumpActivity()
                        onBackgroundTap?(wasHidden)
                    }
                } label: {
                    Color.clear.contentShape(.rect)
                }
                #if os(tvOS)
                // The stock plain style brightens and lifts a focused button; on a
                // full-screen clear label that is a light platter over the whole
                // picture (owner Y1: "washed out", inset rounded card).
                .buttonStyle(AppleTVSurfaceButtonStyle())
                #else
                .buttonStyle(.plain)
                #endif
                .appleVisionHover()
                .accessibilityLabel(chrome.selectTogglesPlayback ? "Play or pause" : "Show playback controls")
                .accessibilityIdentifier("player.controls.show")
                #if os(tvOS)
                .focused($tvFocus, equals: .surface)
                .onMoveCommand { direction in
                    // The surface holds focus while the video plays, so the
                    // clickpad edges skip and a swipe down reveals the controls.
                    switch direction {
                    case .left where model.canSkip: Task { await model.skip(by: -chrome.moveSkipSeconds) }
                    case .right where model.canSkip: Task { await model.skip(by: chrome.moveSkipSeconds) }
                    case .down:
                        model.bumpActivity()
                        if model.nextEpisodePrompt != nil {
                            tvFocus = .nextEpisode
                        } else {
                            tvFocus = model.showsSkipIntro ? .skipIntro : (model.isScrubbable ? .scrubber : .captions)
                        }
                    default: model.bumpActivity()
                    }
                }
                #endif
            }

            #if os(tvOS)
            // The focus engine needs the chrome mounted: a swipe down sets
            // `tvFocus` in the same update that reveals it.
            transportChrome
                .opacity(model.controlsVisible ? 1 : 0)
                .allowsHitTesting(model.controlsVisible)
                .accessibilityHidden(!model.controlsVisible)
            #else
            // Removed, not faded. Fading it left every button on screen as far
            // as touch and assistive technology were concerned: after the
            // three-second auto-hide, "Channels" was still reported at full
            // size, still hittable, and `allowsHitTesting(false)` silently
            // swallowed the tap — so the picker never opened and the tap never
            // reached the reveal surface underneath either (2026-09-18).
            if model.controlsVisible, !isObscured { transportChrome.transition(.opacity) }
            #endif

            // Inside the chrome's fade: the transport auto-hides
            // after three seconds of playback, so these prompts follow
            // the same visibility as the rest of the controls.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    #if os(tvOS)
                    skipIntroButton
                        .opacity(model.controlsVisible ? 1 : 0)
                        .allowsHitTesting(model.controlsVisible)
                        .accessibilityHidden(!model.controlsVisible)
                    #else
                    if model.controlsVisible { skipIntroButton.transition(.opacity) }
                    #endif
                }
                HStack {
                    Spacer()
                    nextEpisodeCard
                }
            }
            .padding(nextEpisodeCardInset)
            // Reserve the real control height, including Dynamic Type, so
            // prompts cannot cover captions or the scrubber. Keep this space
            // when the controls fade to avoid moving the button mid-tap.
            .padding(.bottom, bottomBarHeight + AppleDesignTokens.spacingMedium)

            if model.showsWaitingIndicator { waitingIndicator }
            // Cues sit against the **picture**, not the screen. On Apple TV the
            // video is full-bleed so this adds nothing and the layout is
            // unchanged; on a phone in portrait the video letterboxes into a
            // band and the caption used to float ~450 pt below it, in the black
            // (2026-09-16). See `AppleVideoFitting`.
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    subtitleCueView
                        // Inside the frame, not outside it. Padding applied
                        // *after* `.frame` expands the view instead of lifting
                        // the cue within it — which is why the first attempt
                        // built, passed its geometry tests and changed nothing
                        // on screen (2026-09-16).
                        .padding(.bottom, AppleVideoFitting.captionBottomInset(
                            container: proxy.size,
                            videoSize: coordinator.engine.videoSize
                        ))
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
            .padding(.bottom, model.controlsVisible ? 100 : 24)
            .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .task(id: request.mediaID) {
            // The coordinator's route is not available through `init`, so the
            // view seeds the model here. The DVR window is NOT seeded from the
            // request: `effectiveDVRWindowSeconds` is the engine's retention
            // hint (1800 for every live channel), and the transport reads the
            // player's real seekable range instead — see `liveSeekableRange`.
            model.route = coordinator.route
        }
        .onChange(of: coordinator.engine.avPlayer.map(ObjectIdentifier.init), initial: true) { _, _ in
            isMuted = coordinator.engine.avPlayer?.isMuted ?? false
        }
        .onChange(of: coordinator.phase) { _, _ in model.playbackPhaseChanged() }
        .onChange(of: coordinator.route) { _, newRoute in
            model.route = newRoute
        }
        #if os(tvOS)
        .defaultFocus($tvFocus, .surface)
        .onChange(of: model.controlsVisible) { _, isVisible in
            onControlsVisibilityChanged?(isVisible)
            // Focus returns to the invisible surface when the controls hide,
            // so nothing is drawn as focused during playback.
            if !isVisible, chrome.hidesFocusDuringPlayback { tvFocus = .surface }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onExitCommand {
            // Menu closes the player and returns to the page that opened it.
            if let onClose { onClose() } else { dismiss() }
        }
        #endif
    }

    /// The auto-hiding controls: top bar, centre transport, bottom bar. A tap
    /// anywhere inside them restarts the hide timer instead of hiding them.
    private var transportChrome: some View {
        VStack {
            topBar
            Spacer()
            // No play/pause or skip glyphs on Apple TV: Select, the
            // Play/Pause button and the clickpad edges carry them.
            if chrome.showsPlayPauseGlyph { centerRow }
            Spacer()
            bottomBar
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    bottomBarHeight = $0
                }
        }
        .padding()
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded { model.bumpActivity() })
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            if controls.contains(.close) {
                Button {
                    if let onRequestFullScreen { onRequestFullScreen() }
                    else if let onClose { onClose() }
                    else {
                        coordinator.stop()
                        dismiss()
                    }
                } label: {
                    Image(systemName: onRequestFullScreen == nil ? "xmark" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: AppleDesignTokens.minimumActionSize, height: AppleDesignTokens.minimumActionSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .appleVisionHover()
                .accessibilityLabel(onRequestFullScreen == nil ? "Close player" : "Full Screen")
                .accessibilityIdentifier(onRequestFullScreen == nil ? "player.close" : "player.fullscreen")
            }

            if let onShowChannels {
                Button {
                    model.bumpActivity()
                    onShowChannels()
                } label: {
                    Text("Channels")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(minWidth: AppleDesignTokens.minimumActionSize, minHeight: AppleDesignTokens.minimumActionSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.channels")
            }
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if liveTopControls {
                    captionsToggle
                    AppleTransportTrackMenu(
                        audioTracks: model.audioTracks,
                        subtitleTracks: model.visibleSubtitleTracks,
                        onSelectAudio: { model.selectAudio($0) },
                        onSelectSubtitle: { model.selectSubtitle($0) }
                    )
                }
                if let otherSources, controls.contains(.otherSourcesMenu) {
                    Menu {
                        Button("Other sources", systemImage: "list.bullet", action: otherSources)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: AppleDesignTokens.minimumActionSize, height: AppleDesignTokens.minimumActionSize)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("More")
                }
                if let sharePlayMenu, controls.contains(.sharePlayMenu) {
                    Menu {
                        Button(sharePlayMenu.primaryTitle, action: sharePlayMenu.primaryAction)
                        if let secondaryTitle = sharePlayMenu.secondaryTitle, let secondaryAction = sharePlayMenu.secondaryAction {
                            Button(secondaryTitle, role: .destructive, action: secondaryAction)
                        }
                    } label: {
                        Image(systemName: liveTopControls ? "ellipsis" : "shareplay").frame(width: AppleDesignTokens.minimumActionSize, height: AppleDesignTokens.minimumActionSize)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(liveTopControls ? "More" : "SharePlay")
                    .accessibilityIdentifier("player.more")
                }
                if liveTopControls, let player = coordinator.engine.avPlayer {
                    Button {
                        player.isMuted.toggle()
                        isMuted = player.isMuted
                        model.bumpActivity()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .frame(width: AppleDesignTokens.minimumActionSize, height: AppleDesignTokens.minimumActionSize)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    .accessibilityIdentifier("player.mute")
                }
            }
            if request.isLive, !liveTopControls {
                liveBadge
            }

        }
    }

    private var liveTopControls: Bool {
        #if os(iOS) || os(visionOS)
        request.isLive
        #else
        false
        #endif
    }

    @ViewBuilder
    private var liveBadge: some View {
        if model.isScrubbable {
            // live with DVR: badge is tappable → seek to live edge.
            Button {
                Task { await model.seekToLiveEdge() }
            } label: {
                liveBadgeLabel
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Live")
            .accessibilityValue(model.isAtLiveEdge ? "At the live edge" : "Behind live")
            .accessibilityIdentifier("player.live")
            #if os(tvOS)
            .focusable()
            #endif
        } else {
            liveBadgeLabel
        }
    }

    private var liveBadgeLabel: some View {
        // Red while the stream is at its edge, plain once the viewer has
        // scrubbed back into the DVR window — the same way the TV app's LIVE
        // pill behaves, and the only thing on the screen that says a ten
        // second skip did anything.
        Text("LIVE")
            .font(.caption)
            .bold()
            .foregroundStyle(model.isAtLiveEdge ? Color.red : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    // MARK: - Waiting indicator

    /// A centered spinning circle — no text, no background box, no border.
    /// The coordinator's waiting message is exposed only as an accessibility
    /// label.
    private var waitingIndicator: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .controlSize(.large)
            .accessibilityLabel(model.waitingText)
    }

    // MARK: - Skip intro

    /// Offered only while the position is inside a chapter the stream itself
    /// names as its opening. Sits on the same column and layer as the
    /// end-of-episode card, and for the same reason: it must not disappear
    /// with the auto-hiding transport while it is the thing to act on.
    @ViewBuilder
    private var skipIntroButton: some View {
        if model.showsSkipIntro {
            Button("Skip Intro") { Task { await model.skipIntro() } }
                .buttonStyle(.brandSecondary)
                #if os(tvOS)
                .focused($tvFocus, equals: .skipIntro)
                .onDisappear {
                    if tvFocus == .skipIntro { tvFocus = .surface }
                }
                .onMoveCommand { direction in
                    if direction == .down {
                        model.bumpActivity()
                        tvFocus = model.isScrubbable ? .scrubber : .captions
                    }
                }
                #endif
                .accessibilityIdentifier("player.skipIntro")
                .transition(.opacity)
        }
    }

    // MARK: - Next episode

    /// The card sits on the same column as the rest of the app. tvOS already
    /// insets the overlay by the safe area, so only the remainder is needed
    /// here; other platforms keep the standard large inset.
    private var nextEpisodeCardInset: CGFloat {
        #if os(tvOS)
        AppleTVChromeMetrics.glyphPairTrailingPaddingInsideSafeArea
        #else
        AppleDesignTokens.spacingLarge
        #endif
    }

    /// The end-of-episode card: the next episode's name, a Play pill that
    /// carries the countdown, and a way out.
    ///
    /// It is a card rather than a transport button on purpose — the Apple TV
    /// overlay is deliberately a scrubber and one captions control, and a
    /// permanent Next Episode button would undo that.
    @ViewBuilder
    private var nextEpisodeCard: some View {
        if let prompt = model.nextEpisodePrompt {
            VStack(alignment: .leading, spacing: AppleDesignTokens.spacingMedium) {
                Text(prompt.title)
                    #if os(tvOS)
                    .font(.system(size: AppleTVGuideMetrics.standard.titleFontSize, weight: .semibold))
                    #else
                    .font(.headline)
                    #endif
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Button(prompt.countdownLabel) { model.playNextEpisode() }
                        .buttonStyle(.brandPrimary)
                        #if os(tvOS)
                        .focused($tvFocus, equals: .nextEpisode)
                        #endif
                        .accessibilityIdentifier("player.nextEpisode.play")
                    Button("Not Now") { model.dismissNextEpisode() }
                        .buttonStyle(.brandSecondary)
                        .accessibilityIdentifier("player.nextEpisode.dismiss")
                }
            }
            // The app's own tokens rather than one-off numbers: the surface
            // colour every card uses and the card corner radius. A 0.75 black
            // panel with a 16 pt radius was this card's alone and read as a
            // foreign object over the picture.
            .padding(AppleDesignTokens.spacingLarge)
            .background(
                AppleDesignTokens.surface.opacity(0.94),
                in: .rect(cornerRadius: AppleDesignTokens.cornerRadiusCard, style: .continuous)
            )
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            #if os(tvOS)
            // The card is the thing to act on while it is up, so focus lands
            // there rather than leaving the remote on the scrubber.
            .onAppear { tvFocus = .nextEpisode }
            .onDisappear {
                if tvFocus == .nextEpisode { tvFocus = .surface }
            }
            #endif
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if controls.contains(.scrubber) {
                #if os(tvOS)
                AppleTransportScrubberRow(
                    model: model,
                    height: chrome.scrubberHeight,
                    tvFocus: $tvFocus,
                    // Reach the chapter action above the scrubber when it is
                    // present; otherwise keep focus on a visible control.
                    onMoveUp: { tvFocus = model.showsSkipIntro ? .skipIntro : (controls.contains(.captions) ? .captions : .surface) },
                    onMoveDown: { tvFocus = controls.contains(.captions) ? .captions : .surface }
                )
                #else
                AppleTransportScrubberRow(model: model, height: chrome.scrubberHeight)
                #endif
            }
            HStack {
                if liveTopControls { liveBadge }
                Spacer()
                if controls.contains(.captions), !liveTopControls {
                    // The quick key, then the menu where a different track or
                    // audio language is chosen.
                    captionsToggle
                    AppleTransportTrackMenu(
                        audioTracks: model.audioTracks,
                        subtitleTracks: model.visibleSubtitleTracks,
                        onSelectAudio: { model.selectAudio($0) },
                        onSelectSubtitle: { model.selectSubtitle($0) }
                    )
                    #if os(tvOS)
                    .focused($tvFocus, equals: .captions)
                    #endif
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// The quick CC key.
    ///
    /// Apple TV does not get it. The owner's standing rule for that platform is
    /// one captions control and no boxed icons (AGENTS.md §4), and the Siri
    /// Remote already reaches the existing menu in one click — a second
    /// focusable next to it would cost a focus move to gain a tap. Everywhere
    /// there is a finger or a pointer, the key sits left of the menu: instant
    /// on/off there, choosing among tracks in the menu.
    @ViewBuilder
    private var captionsToggle: some View {
        #if !os(tvOS)
        if model.showsCaptionsToggle {
            AppleCaptionsToggleButton(isOn: model.isCCActive) { model.toggleCaptions() }
        }
        #endif
    }

    /// Big centered play/pause flanked by 10 s skip buttons.
    private var centerRow: some View {
        HStack(spacing: 48) {
            if model.canSkip { skipButton(seconds: -10, systemName: "gobackward.10") }
            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .frame(minWidth: AppleDesignTokens.minimumActionSize, minHeight: AppleDesignTokens.minimumActionSize)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .appleVisionHover()
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .appleVisionActionTarget()
            .accessibilityIdentifier("player.play-pause")
            #if os(tvOS)
            .focusable()
            #endif

            if model.canSkip { skipButton(seconds: 10, systemName: "goforward.10") }
        }
    }

    @ViewBuilder
    private func skipButton(seconds: Double, systemName: String) -> some View {
        Button {
            Task { await model.skip(by: seconds) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(minWidth: AppleDesignTokens.minimumActionSize, minHeight: AppleDesignTokens.minimumActionSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
            .appleVisionHover()
        .accessibilityLabel(seconds < 0 ? "Back 10 seconds" : "Forward 10 seconds")
        .accessibilityIdentifier(seconds < 0 ? "player.skip-back" : "player.skip-forward")
        #if os(tvOS)
        .focusable()
        #endif
    }

    /// The active subtitle cue rendered at the bottom of the surface. Text and
    /// rich-text cues render as a centred label; `.image` cues (PGS/DVB) render
    /// as the decoded bitmap. Hidden when no cue overlaps the current position.
    @ViewBuilder
    private var subtitleCueView: some View {
        if let cue = model.activeSubtitleCue {
            subtitleCueLabel(for: cue)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .shadow(color: .black, radius: 2)
        }
    }

    @ViewBuilder
    private func subtitleCueLabel(for cue: AppleSubtitleCue) -> some View {
        switch cue.body {
        case .text(let s):
            Text(s)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        case .richText(let runs):
            Text(runs.map(\.text).joined())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        case .image(let cgImage):
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 120)
        }
    }

    // MARK: - Helpers

    private var isPlaying: Bool {
        if case .playing = coordinator.phase { return true }
        return false
    }
}

/// The scrubber row (position text, slider/bar, remaining time). Extracted so
/// its Observation tracking is scoped to `position`/`progress`/`duration`
/// only, keeping sibling controls (e.g. the track menu) from being
/// re-evaluated on every position tick.
@MainActor
private struct AppleTransportScrubberRow: View {
    let model: AppleTransportOverlayModel
    let height: CGFloat
    #if os(tvOS)
    let tvFocus: FocusState<AppleTransportOverlay.TVFocus?>.Binding
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    #endif

    var body: some View {
        HStack(spacing: 12) {
            Text(model.positionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
            #if os(tvOS)
            tvosScrubber
            #else
            Slider(value: Binding(
                get: { model.progress },
                set: { fraction in Task { await model.scrub(to: fraction) } }
            ), in: 0...1)
            .tint(.white)
            .appleVisionActionTarget()
            .accessibilityLabel("Playback position")
            .accessibilityValue(model.positionText)
            #endif
            Text(remainingText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    /// Remaining time as `-m:ss` (or `-h:mm:ss`). Empty for live.
    private var remainingText: String {
        if model.isLive { return "" }
        guard let duration = model.duration, duration > 0 else { return "" }
        let remaining = max(0, duration - model.position)
        return "-" + AppleTransportOverlayModel.timeText(remaining)
    }

    #if os(tvOS)
    /// `Slider` is unavailable on tvOS, so the scrubber is a focusable bar
    /// driven by the remote's left/right `onMoveCommand`.
    private var tvosScrubber: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(tvFocus.wrappedValue == .scrubber ? 0.45 : 0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * model.progress)
            }
            .frame(height: height)
            .focusable()
            .focused(tvFocus, equals: .scrubber)
            .onMoveCommand { direction in
                switch direction {
                case .left: Task { await model.scrub(to: model.progress - 0.05) }
                case .right: Task { await model.scrub(to: model.progress + 0.05) }
                case .up: onMoveUp()
                case .down: onMoveDown()
                @unknown default: break
                }
            }
        }
        .frame(height: height)
    }
    #endif
}

/// The single secondary control: a "Audio & Subtitles" menu grouping the
/// audio track choices and the subtitle (Off + tracks) choices. Extracted
/// into its own view so its Observation tracking depends only on the track
/// arrays passed in, not on the overlay's per-tick position state — an open
/// `Menu` inside a view that also reads `position` gets torn down and
/// rebuilt on every position update, which flashes the menu and drops taps.
@MainActor
struct AppleTransportTrackMenu: View {
    let audioTracks: [ApplePlaybackTrack]
    let subtitleTracks: [ApplePlaybackTrack]
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void

    var body: some View {
        Menu {
            if audioTracks.count > 1 {
                Section("Audio") {
                    ForEach(audioTracks) { track in
                        Button(trackLabel(track)) {
                            onSelectAudio(track.id)
                        }
                    }
                }
            }
            Section("Subtitles") {
                Button("Off") { onSelectSubtitle(nil) }
                ForEach(subtitleTracks) { track in
                    Button(AppleSubtitleTrackFilter.menuLabel(for: track)) {
                        onSelectSubtitle(track.id)
                    }
                    .accessibilityIdentifier("player.subtitle.track.\(track.id)")
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 22))
                .frame(width: AppleDesignTokens.minimumActionSize, height: AppleDesignTokens.minimumActionSize)
                .contentShape(.rect)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Audio & Subtitles")
        .accessibilityIdentifier("player.captions")
        #if os(tvOS)
        // A `.focusable()` wrapper used to take the focus and swallow Select,
        // so the menu never opened (owner 16:27). The menu is focusable on its
        // own; a bare glyph disc replaces the stock boxed button.
        .menuStyle(.button)
        .buttonStyle(AppleTVGlyphStyle())
        #endif
    }

    private func trackLabel(_ track: ApplePlaybackTrack) -> String {
        if let language = track.language, !language.isEmpty {
            return "\(track.title) (\(language))"
        }
        return track.title
    }
}
