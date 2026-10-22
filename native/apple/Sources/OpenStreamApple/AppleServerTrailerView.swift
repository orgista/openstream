import AVFoundation
import AVKit
import Observation
import SwiftUI

/// One server trailer's player. It counts as on screen once its clock has
/// moved `AppleTrailerRevealPolicy.minimumMediaAdvance`: frames are flowing,
/// not a first buffer. With `watchdog` (a hero's, which nobody pauses), one
/// whose clock stands still for `AppleTrailerArtFirstPolicy.startupTimeout`,
/// at the start or later, has failed: the still comes back and the carousel
/// moves on rather than hold a frozen frame.
@MainActor
@Observable
final class AppleServerTrailerPlayback {
    enum Phase: Equatable { case idle, loading, playing, ended, failed }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private(set) var player: AVPlayer?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var lastProgress = (media: -1.0, at: Date.distantPast)

    func start(_ trailer: AppleServerTrailer, muted: Bool, watchdog usesWatchdog: Bool = true) {
        stop()
        let item = AVPlayerItem(url: trailer.url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted || AppleTestAudioMute.isActive
        appleTrace("server trailer start \(muted ? "muted" : "with sound")\(AppleTestAudioMute.isActive ? " (test mute on)" : "")")
        #if !os(visionOS)
        player.preventsDisplaySleepDuringVideoPlayback = false
        #endif
        self.player = player
        phase = .loading
        lastProgress = (-1, .now)
        // Every callback checks it is still this item's: a late one from a
        // replaced player must not end the new one.
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.finish(.failed, for: item) }
        }
        // These deliver on the main queue, so they are on the main actor.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.advance(to: time.seconds) }
        }
        let center = NotificationCenter.default
        itemObservers = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.ended, for: item) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.failed, for: item) }
            },
        ]
        if usesWatchdog {
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    if Date.now.timeIntervalSince(self.lastProgress.at) >= AppleTrailerArtFirstPolicy.startupTimeout {
                        self.finish(.failed, for: item)
                    }
                }
            }
        }
        player.play()
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted || AppleTestAudioMute.isActive
    }

    func stop() {
        player?.pause()
        watchdog?.cancel()
        watchdog = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        statusObservation = nil
        timeObserver = nil
        itemObservers = []
        player = nil
        phase = .idle
    }

    private func advance(to media: Double) {
        guard media.isFinite, media > lastProgress.media else { return }
        lastProgress = (media, .now)
        if phase == .loading, media >= AppleTrailerRevealPolicy.minimumMediaAdvance { phase = .playing }
    }

    private func finish(_ phase: Phase, for item: AVPlayerItem) {
        guard player?.currentItem === item, self.phase == .loading || self.phase == .playing else { return }
        if phase == .failed { appleTraceFailure("server trailer failed to play") }
        stop()
        self.phase = phase
    }
}

#if os(tvOS) || os(visionOS)
/// A hero's server trailer, under the Apple TV app's rules
/// (`AppleHeroTrailerGate`, art-first): muted autoplay once the still is
/// up, or with sound when Play Trailer was pressed. It reports to the
/// carousel (`AppleHomeHeroTrailerStateKey`), which holds the page while it
/// plays and moves on after it ends.
struct AppleHeroServerTrailer: View {
    let trailer: AppleServerTrailer
    let settings: AppleSettingsStore
    let art: AppleTrailerArtFirstPolicy.Art
    var trailerRequest: UUID? = nil
    var onScreen: (Bool) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appleHeroIsCovered) private var isCovered
    @State private var isVisible = false
    @State private var isPresented = false
    @State private var phase: AppleServerTrailerPlayback.Phase = .idle
    @State private var lastEnd: UUID?
    #if os(visionOS)
    @State private var systemVideoAutoplay = UIAccessibility.isVideoAutoplayEnabled
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    #endif

    private var plays: Bool {
        #if os(visionOS)
        let (systemVideoAutoplay, lowPower) = (systemVideoAutoplay, lowPower)
        #else
        let (systemVideoAutoplay, lowPower) = (true, false)
        #endif
        return AppleHeroTrailerGate.plays(.init(
            autoPlaySetting: settings.autoPlayTrailer, reduceMotion: reduceMotion, lowPower: lowPower,
            systemVideoAutoplay: systemVideoAutoplay, sceneIsActive: scenePhase == .active, halfVisible: isVisible,
            isPresented: isPresented, isCovered: isCovered, art: art, pressed: trailerRequest != nil))
    }

    var body: some View {
        ZStack {
            Color.clear
            AppleServerTrailerStage(trailer: trailer, plays: plays, muted: trailerRequest == nil,
                                    restart: trailerRequest) { phase = $0 }
        }
        .onAppear { isPresented = true }
        .onDisappear {
            isPresented = false
            if phase == .playing { onScreen(false) }
        }
        .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
        .onChange(of: phase) { old, new in
            if new == .ended { lastEnd = UUID() }
            if (old == .playing) != (new == .playing) { onScreen(new == .playing) }
        }
        .preference(key: AppleHomeHeroTrailerStateKey.self,
                    value: .init(isPlaying: phase == .loading || phase == .playing, isOnScreen: phase == .playing,
                                 isMuted: trailerRequest == nil, isRequested: trailerRequest != nil, lastEnd: lastEnd))
        #if os(visionOS)
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
            systemVideoAutoplay = UIAccessibility.isVideoAutoplayEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        #endif
    }
}

/// A server trailer over a still: aspect-filled into the frame with no
/// bars, invisible until it plays, then faded in. It plays once; at the end
/// or on a failure the still shows again. A new `restart` starts it over.
struct AppleServerTrailerStage: View {
    let trailer: AppleServerTrailer
    /// The hero's gate: false takes it down.
    let plays: Bool
    var muted = true
    var restart: UUID? = nil
    var onPhase: (AppleServerTrailerPlayback.Phase) -> Void = { _ in }
    @State private var playback = AppleServerTrailerPlayback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Run: Equatable {
        let url: URL
        let plays: Bool
        let restart: UUID?
    }

    var body: some View {
        AppleServerTrailerLayer(player: playback.player)
            .opacity(playback.phase == .playing ? 1 : 0)
            .animation(.easeInOut(duration: AppleTrailerArtFirstPolicy.crossfadeDuration(reduceMotion: reduceMotion)),
                       value: playback.phase)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier("hero.serverTrailer")
            .accessibilityValue(playback.phase == .playing ? "playing" : "still")
            .task(id: Run(url: trailer.url, plays: plays, restart: restart)) {
                // Muted, it still takes `.ambient`: a muted player on the
                // session the last title left would stop the viewer's music.
                guard plays, await ApplePlaybackSessionPolicy.prepareTrailerAudioAwaiting(pressed: !muted) else {
                    playback.stop()
                    return
                }
                playback.start(trailer, muted: muted)
            }
            .onChange(of: muted) { playback.setMuted(muted) }
            .onChange(of: playback.phase) { onPhase(playback.phase) }
            .onDisappear { playback.stop() }
    }
}

/// The trailer's picture in an `AVPlayerLayer`, filling its frame.
private struct AppleServerTrailerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> LayerView { LayerView() }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { nil }
    }
}
#endif

/// A server trailer full screen, with sound and the system's controls:
/// what the title page's Trailer button opens. It closes itself at the end.
struct AppleServerTrailerPlayerView: View {
    let trailer: AppleServerTrailer
    let onClose: () -> Void
    @State private var playback = AppleServerTrailerPlayback()

    var body: some View {
        VideoPlayer(player: playback.player)
            .ignoresSafeArea()
            .background(.black)
            .overlay {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(playback.phase == .playing ? "trailer.player.playing" : "trailer.player.loading")
                    .allowsHitTesting(false)
            }
            .onAppear {
                #if os(iOS) || os(tvOS) || os(visionOS)
                ApplePlaybackSessionPolicy.prepareTrailerAudio(pressed: true)
                #endif
                // The viewer may pause it: no watchdog here.
                playback.start(trailer, muted: false, watchdog: false)
            }
            .onChange(of: playback.phase) {
                if playback.phase == .ended || playback.phase == .failed { onClose() }
            }
            .onDisappear { playback.stop() }
    }
}

extension View {
    /// Plays `trailer` while `isPresented`: a full-screen cover on iPhone,
    /// iPad, Apple TV and Vision Pro; over the window on the Mac, as its
    /// player is (`AppleMacPlayerStage`), never a sheet.
    func appleServerTrailerPresentation(_ trailer: AppleServerTrailer?, isPresented: Binding<Bool>) -> some View {
        modifier(AppleServerTrailerPresenter(trailer: trailer, isPresented: isPresented))
    }
}

private struct AppleServerTrailerPresenter: ViewModifier {
    let trailer: AppleServerTrailer?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay {
            if isPresented, let trailer {
                AppleServerTrailerPlayerView(trailer: trailer) { isPresented = false }
                    .overlay(alignment: .topLeading) {
                        Button { isPresented = false } label: {
                            AppleTitlePageMacRoundLabel(title: "Close", systemImage: "xmark")
                        }
                        .buttonStyle(AppleMacHeroButtonStyle(kind: .round))
                        .keyboardShortcut(.cancelAction)
                        .padding(20)
                    }
                    .transition(.opacity)
            }
        }
        #else
        content.fullScreenCover(isPresented: $isPresented) {
            if let trailer {
                AppleServerTrailerPlayerView(trailer: trailer) { isPresented = false }
            }
        }
        #endif
    }
}
