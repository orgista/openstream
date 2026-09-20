import Foundation
import Observation

/// Backing model for `AppleTransportOverlay` on `.surface` routes. It mirrors
/// the engine's position/duration/tracks through `events` into observable
/// stored properties, applies the transport policy table (scrubbability, time
/// formatting, live/DVR behaviour), and owns the 3-second control auto-hide
/// timer. The view stays declarative; this type owns the state.
///
/// Per T7e the overlay exists only on `.surface` routes; on `.avPlayer`
/// routes the system player UI owns every control, so `showsOverlay` is
/// `false` and no custom waiting indicator is ever shown.
///
/// Policy table (see T5 spec):
/// - VOD with a known duration → scrubber enabled, `m:ss` / `h:mm:ss` times.
/// - live the player reports no usable rewind for → scrubber and skip buttons
///   hidden, "LIVE" badge, empty times.
/// - live with a real seekable range (`liveSeekableRange`, wider than
///   `AppleLiveSeekPolicy.minimumUsefulSpan`) → scrubber over that range; the
///   "LIVE" badge is tappable to seek back to the live edge.
@MainActor
@Observable
public final class AppleTransportOverlayModel {
    /// The coordinator whose engine is driving playback.
    public let coordinator: ApplePlaybackCoordinator

    /// Whether the current request is a live stream. Set once at construction;
    /// the view passes `request.isLive`.
    public let isLive: Bool

    /// What the stream can ACTUALLY be seeked within, mirrored from the engine
    /// on every position tick. Nil until the player reports one, and nil for a
    /// live-edge-only source that can never rewind.
    ///
    /// Every live seek and every live readout is computed from this, not from
    /// `dvrWindowSeconds`: that number is the load hint, identical (1800) for
    /// every live channel, and clamping against it is why skip-back on a live
    /// channel moved nothing a viewer could see (owner, GUI audit 2026-09-19).
    public private(set) var liveSeekableRange: AppleSeekableRange? = nil

    /// Presentation route. Seeded from the coordinator in `init` and updated
    /// when the engine emits a `.route` event; drives whether the overlay and
    /// its waiting indicator are shown at all.
    public var route: ApplePlaybackPresentationRoute = .none

    /// Starts the next episode. Set by whatever presented the player and knows
    /// the season; nil for a movie, a live channel or the last episode.
    public var nextEpisode: (() -> Void)? = nil
    /// The next episode's `displayTitle`, for the card to name it. Set
    /// alongside `nextEpisode`; one without the other offers nothing.
    public var nextEpisodeTitle: String? = nil
    /// The viewer's "Auto Play Next Episode" setting. With it off the card
    /// still appears and still works — only the unattended start stops.
    public var autoPlayNextEpisode: Bool = true
    /// Set when the viewer dismisses the card, which also stops the
    /// auto-advance for the rest of the episode. Cleared on the next load.
    public private(set) var nextEpisodeDismissed = false
    /// Guards against firing the advance twice: the position observer ticks
    /// four times a second and the end can be reported more than once.
    @ObservationIgnored private var hasAdvancedToNextEpisode = false

    /// The stream's opening sequence, from its own chapter markers. Nil for
    /// content that carries none, which is most of it — see
    /// `AppleChapterMarkers`.
    public var introChapter: AppleChapter? = nil
    /// Sticky for the rest of the item: seeking back into the opening after
    /// skipping must not put the button up again. It ends with the item —
    /// see `clearIntroForNewItem()`, because this model outlives a load
    /// whenever the viewer switches source or channel inside the player.
    public private(set) var hasSkippedIntro = false

    /// Whether the Skip Intro button belongs on screen right now.
    public var showsSkipIntro: Bool {
        AppleChapterMarkers.shouldOfferSkip(
            position: position,
            intro: introChapter,
            hasSkipped: hasSkippedIntro
        )
    }

    /// Seeks to the first frame after the opening, through the same
    /// coordinator path the scrubber uses.
    public func skipIntro() async {
        guard let introChapter else { return }
        hasSkippedIntro = true
        bumpActivity()
        let destination = AppleChapterMarkers.skipDestination(intro: introChapter)
        appleTrace("skip intro → \(Int(destination))s")
        await coordinator.userSeek(to: destination)
    }

    /// Re-derives the opening from the engine's markers and whatever runtime is
    /// known now. Idempotent and write-guarded, so calling it from both
    /// `.tracks` and `.duration` costs no extra Observation invalidation.
    private func refreshIntroChapter() {
        let found = AppleChapterMarkers.intro(in: coordinator.engine.chapters, duration: duration)
        if introChapter != found { introChapter = found }
    }

    /// Re-reads the engine's real seekable span. Write-guarded: the position
    /// observer ticks four times a second and an unchanged range must not
    /// invalidate every Observation reader of this model.
    private func refreshSeekableRange() {
        // Live only. A VOD item's seekable range grows as it buffers, and
        // mirroring that at four ticks a second would invalidate every
        // Observation reader of this model — the track menu included — for a
        // value nothing on a VOD screen reads.
        let found = isLive ? coordinator.engine.seekableRange : nil
        if liveSeekableRange != found { liveSeekableRange = found }
    }

    /// Drops the opening and the sticky skip when the engine leaves the item.
    private func clearIntroForNewItem() {
        if introChapter != nil { introChapter = nil }
        if hasSkippedIntro { hasSkippedIntro = false }
    }

    /// The end-of-episode card, or nil when there is nothing to offer yet.
    public var nextEpisodePrompt: AppleNextEpisodePrompt? {
        guard nextEpisode != nil else { return nil }
        return AppleNextEpisodePolicy.prompt(
            position: position,
            duration: duration,
            nextTitle: nextEpisodeTitle,
            isLive: isLive,
            isDismissed: nextEpisodeDismissed
        )
    }

    /// The viewer saying "no". Hides the card and cancels the auto-advance
    /// until another episode loads.
    public func dismissNextEpisode() {
        nextEpisodeDismissed = true
        bumpActivity()
    }

    /// Starts the next episode now, from the card.
    public func playNextEpisode() {
        guard let nextEpisode else { return }
        hasAdvancedToNextEpisode = true
        nextEpisode()
    }

    /// Whether the transport controls are currently visible. Auto-hides 3 s
    /// after the last interaction while playing; any interaction re-shows them.
    public private(set) var controlsVisible: Bool = true

    // MARK: - Mirrored engine state

    public private(set) var position: Double = 0
    public private(set) var duration: Double? = nil
    public private(set) var audioTracks: [ApplePlaybackTrack] = []
    /// Every embedded track, unfiltered. `visibleSubtitleTracks` is what the
    /// captions menu lists.
    public private(set) var subtitleTracks: [ApplePlaybackTrack] = []

    /// The viewer's chosen subtitle languages, used to shorten the menu.
    /// Empty means "no preference", which lists every track.
    public var preferredSubtitleLanguages: [String] = []
    /// See `AetherPlaybackEngine.subtitleLanguagesAreExplicit`.
    public var subtitleLanguagesAreExplicit = false

    /// The captions menu's list: the tracks in the viewer's languages. Falls
    /// back to every track only when the languages were inferred from the
    /// device rather than picked.
    public var visibleSubtitleTracks: [ApplePlaybackTrack] {
        AppleSubtitleTrackFilter.visible(
            subtitleTracks,
            preferredLanguages: preferredSubtitleLanguages,
            isExplicitChoice: subtitleLanguagesAreExplicit)
    }

    /// Decoded cues for the active subtitle track, mirrored from the engine for
    /// the overlay to render on `.surface`. Empty on `.avPlayer` routes where the
    /// system player's captions menu renders the track.
    public private(set) var subtitleCues: [AppleSubtitleCue] = []

    /// The subtitle track the user selected through the overlay, tracked locally
    /// so the CC button reflects the selection immediately (before the engine
    /// confirms it) and so the model test can assert it without a live engine.
    public private(set) var selectedSubtitleID: Int? = nil

    // MARK: - Private

    private var observationTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// Three seconds of stillness hides the chrome. A UI test cannot read a
    /// button's frame and its neighbour's inside that window — the second query
    /// lands after the timer — so the crawler and the live photo tests launch
    /// with `-OpenStreamHoldPlayerChrome YES` and the timer stands down.
    private let hideDelay: Duration = AppleTransportOverlayModel.chromeIsHeldOpen ? .seconds(600) : .seconds(3)

    static let chromeIsHeldOpen: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-OpenStreamHoldPlayerChrome")
            || UserDefaults.standard.bool(forKey: "OpenStreamHoldPlayerChrome")
        #else
        return false
        #endif
    }()

    public init(coordinator: ApplePlaybackCoordinator, isLive: Bool) {
        self.coordinator = coordinator
        self.isLive = isLive
        // Seed from the engine's current synchronous state so the first render
        // is correct before any event has been emitted.
        self.position = coordinator.engine.position
        self.duration = coordinator.engine.duration
        self.audioTracks = coordinator.engine.audioTracks
        self.subtitleTracks = coordinator.engine.subtitleTracks
        self.introChapter = AppleChapterMarkers.intro(
            in: coordinator.engine.chapters,
            duration: coordinator.engine.duration
        )
        // The same persisted list the coordinator reads when no host hands it
        // one, so the menu and the auto-selection agree on the languages. The
        // key existing *is* the explicit choice — `AppleSettingsStore` derives
        // `hasChosenSubtitleLanguages` from exactly this — so a viewer who
        // picked English gets a menu of English and nothing else.
        let chosen = UserDefaults.standard.stringArray(forKey: AppleSubtitleLanguages.defaultsKey)
        self.preferredSubtitleLanguages = chosen ?? []
        self.subtitleLanguagesAreExplicit = chosen != nil
        self.route = coordinator.route
        self.liveSeekableRange = isLive ? coordinator.engine.seekableRange : nil
        // The engine may already have auto-selected a track from the viewer's
        // captions preference before the overlay existed. Without this the CC
        // key would open reading "off" over a picture with captions on it.
        self.selectedSubtitleID = coordinator.engine.activeSubtitleTrackID
        startObserving()
        scheduleAutoHide()
    }

    // MARK: - Overlay visibility

    /// The custom overlay exists only on `.surface` routes. On `.avPlayer`
    /// routes the system player UI owns every control.
    public var showsOverlay: Bool { route == .surface }

    /// `true` when the centered spinning waiting indicator should be shown.
    /// Only on `.surface` routes, and only before the player is ready
    /// (`.resolving` / `.loading`) or while it is buffering / reconnecting
    /// (`.waiting`). On `.avPlayer` routes the system player shows its own
    /// spinner, so this is always `false`.
    public var showsWaitingIndicator: Bool {
        guard route == .surface else { return false }
        switch coordinator.phase {
        case .resolving, .loading, .waiting:
            return true
        default:
            return false
        }
    }

    /// Text for the waiting indicator's accessibility label. The spinner has
    /// no visible text; this string (the coordinator's waiting message, or a
    /// default while resolving/loading) is exposed to VoiceOver only.
    public var waitingText: String {
        switch coordinator.phase {
        case .waiting(let message): return message ?? "Preparing playback"
        case .resolving: return "Resolving stream"
        case .loading: return "Loading stream"
        default: return "Preparing playback"
        }
    }

    // MARK: - Policy-derived views

    /// `true` when the scrubber should be shown and accept input.
    public var isScrubbable: Bool {
        if isLive {
            // The window the player proves it holds, not the one the request
            // asked for. A sliding-window IPTV playlist with three segments in
            // it gets no scrubber, because there is nothing to scrub.
            return AppleLiveSeekPolicy.offersDVR(liveSeekableRange)
        }
        // VOD: scrubbable once a positive duration is known.
        return (duration ?? 0) > 0
    }

    /// How far behind the live edge the viewer still counts as being at it.
    /// A seek lands a fraction of a second off, and a stream's own edge moves
    /// while the seek is in flight.
    public static let liveEdgeTolerance: Double = 5

    /// `true` while a live stream is playing at its edge — always true for a
    /// live stream with no DVR window, because there is nowhere else to be.
    ///
    /// The LIVE badge is drawn from this. Without it, skipping back ten
    /// seconds on a channel with a DVR window changed nothing a viewer could
    /// see: the badge stayed red, the thumb moved a tenth of a percent, and
    /// live carries no time readout (button crawl, 2026-09-19).
    public var isAtLiveEdge: Bool {
        guard isLive else { return false }
        return AppleLiveSeekPolicy.isAtLiveEdge(
            position: position,
            in: liveSeekableRange,
            tolerance: Self.liveEdgeTolerance
        )
    }

    /// `true` when the ±10 s skip buttons belong on screen: they move the
    /// picture. A live channel with no rewind gets none rather than two that
    /// look enabled and swallow the tap.
    public var canSkip: Bool {
        if isLive { return AppleLiveSeekPolicy.offersDVR(liveSeekableRange) }
        return (duration ?? 0) > 0
    }

    /// `m:ss` or `h:mm:ss` for VOD; empty for live (the LIVE badge carries the
    /// status, DVR or not).
    public var positionText: String {
        isLive ? "" : Self.timeText(position)
    }

    /// Duration label. For VOD this is the media duration; for a DVR live
    /// stream it is the window length; empty for plain live.
    public var durationText: String {
        if isLive {
            guard let range = liveSeekableRange, AppleLiveSeekPolicy.offersDVR(range) else { return "" }
            return Self.timeText(range.span)
        }
        guard let duration, duration > 0 else { return "" }
        return Self.timeText(duration)
    }

    /// `0...1` position within the scrubbed window (media duration for VOD,
    /// DVR window for live-with-DVR). `0` when not scrubbable.
    public var progress: Double {
        guard isScrubbable, position >= 0 else { return 0 }
        if isLive {
            return AppleLiveSeekPolicy.progress(position: position, in: liveSeekableRange)
        }
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    // MARK: - Actions

    public func togglePlayPause() {
        bumpActivity()
        if case .playing = coordinator.phase {
            coordinator.userPause()
        } else {
            coordinator.userPlay()
        }
    }

    /// Seek to `fraction` of the scrubbed window (`0...1`).
    public func scrub(to fraction: Double) async {
        bumpActivity()
        let target: Double
        if isLive {
            guard let live = AppleLiveSeekPolicy.scrubTarget(fraction: fraction, in: liveSeekableRange) else { return }
            target = live
        } else {
            guard let duration, duration > 0 else { return }
            target = min(1, max(0, fraction)) * duration
        }
        await coordinator.userSeek(to: target)
    }

    /// Seek back to the live edge of the DVR window. Bound to the "LIVE" badge.
    public func seekToLiveEdge() async {
        guard isLive, let range = liveSeekableRange, AppleLiveSeekPolicy.offersDVR(range) else { return }
        bumpActivity()
        await coordinator.userSeek(to: range.end)
    }

    public func selectAudio(_ id: Int) {
        bumpActivity()
        coordinator.engine.selectAudioTrack(id: id)
    }

    public func selectSubtitle(_ id: Int?) {
        bumpActivity()
        selectedSubtitleID = id
        coordinator.engine.selectSubtitleTrack(id: id)
    }

    /// True when a subtitle track is selected. The CC key reads pressed-in
    /// while this is set; "Off" clears it. Seeded from the engine's own
    /// selection and then driven by the overlay, so it is the immediate,
    /// testable signal that captions are on screen.
    public var isCCActive: Bool { AppleCaptionsToggle.isOn(selected: selectedSubtitleID) }

    /// Whether the CC key is drawn: only when there is a preferred-language
    /// track for it to turn on.
    public var showsCaptionsToggle: Bool {
        AppleCaptionsToggle.isAvailable(visible: visibleSubtitleTracks)
    }

    /// One tap: on selects the preferred-language track, off clears it. The
    /// Audio & Subtitles menu stays the place a *different* track is chosen.
    public func toggleCaptions() {
        selectSubtitle(
            AppleCaptionsToggle.nextSelection(
                selected: selectedSubtitleID,
                visible: visibleSubtitleTracks
            )
        )
    }

    /// The cue active at the current position, for the overlay to render on
    /// `.surface`. nil when no track is selected, no cue overlaps the position,
    /// or the route is `.avPlayer` (cues are empty there — the system captions
    /// menu renders the track).
    public var activeSubtitleCue: AppleSubtitleCue? {
        guard !subtitleCues.isEmpty else { return nil }
        return subtitleCues.first { position >= $0.startTime && position < $0.endTime }
    }

    // MARK: - Route-derived secondary actions

    /// AirPlay button is shown on `.avPlayer` routes (a real route picker);
    /// on `.surface` it shows the unavailable hint instead. The T7e overlay no
    /// longer renders either button, but the model still reports the route.
    public var showsAirPlay: Bool { route == .avPlayer }

    /// Picture-in-picture button is shown on `.avPlayer` routes on iOS
    /// (toggles PiP through the AVKit controller). tvOS has no PiP;
    /// `.surface` hides it. The T7e overlay no longer renders it.
    public var showsPictureInPicture: Bool {
        #if os(iOS)
        return route == .avPlayer
        #else
        return false
        #endif
    }

    /// `true` when a "Next Episode" action is wired.
    public var showsNextEpisode: Bool { nextEpisode != nil }

    /// Starts the next episode once this one has run out, unless the viewer
    /// turned auto-play off or dismissed the card.
    private func advanceToNextEpisodeIfDue() {
        guard !hasAdvancedToNextEpisode, let nextEpisode else { return }
        guard AppleNextEpisodePolicy.shouldAutoAdvance(
            position: position,
            duration: duration,
            nextTitle: nextEpisodeTitle,
            isLive: isLive,
            isDismissed: nextEpisodeDismissed,
            isEnabled: autoPlayNextEpisode
        ) else { return }
        hasAdvancedToNextEpisode = true
        appleTrace("next episode auto-advance → \(nextEpisodeTitle ?? "?")")
        nextEpisode()
    }

    // MARK: - Skip

    /// Skip by `seconds` (typically ±10). Clamped to `[0, duration]` for VOD
    /// and to the stream's real seekable range for live; a no-op for a live
    /// source with no rewind, and for a move the range leaves nowhere to go.
    public func skip(by seconds: Double) async {
        bumpActivity()
        let target: Double
        if isLive {
            guard let live = AppleLiveSeekPolicy.skipTarget(
                from: position, by: seconds, in: liveSeekableRange
            ) else {
                appleTrace("live skip \(Int(seconds))s ignored — seekable \(liveSeekableRange.map { "\(Int($0.start))–\(Int($0.end))s" } ?? "none") at \(Int(position))s")
                return
            }
            target = live
        } else {
            guard let duration, duration > 0 else { return }
            target = min(duration, max(0, position + seconds))
        }
        appleTrace("skip \(Int(seconds))s: \(Int(position))s → \(Int(target))s")
        await coordinator.userSeek(to: target)
    }

    /// Called by the view on any user interaction (tap, focus move, remote
    /// press). Re-shows the controls and restarts the auto-hide timer.
    public func bumpActivity() {
        controlsVisible = true
        scheduleAutoHide()
    }

    public func hideControls() {
        controlsVisible = false
        hideTask?.cancel()
    }

    // MARK: - Formatting

    /// `m:ss` for streams under an hour, `h:mm:ss` once ≥ 1 h. Pure static so
    /// tests can assert it without a model instance.
    public static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Engine observation

    private func startObserving() {
        observationTask?.cancel()
        let engine = coordinator.engine
        let events = engine.events
        observationTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { break }
                self.apply(event)
            }
        }
    }

    private func apply(_ event: ApplePlaybackEngineEvent) {
        switch event {
        case .phase(let phase):
            // A new load runs through the engine's `stop()`, which reports
            // `.idle`; from here that is the only load boundary in sight (the
            // coordinator's attempt counter is private). The opening belongs to
            // the item, so both the marker and the skip end with it.
            if phase == .idle { clearIntroForNewItem() }
            // A load boundary replaces the item and with it the window.
            refreshSeekableRange()
            // Phase is otherwise read directly from the coordinator;
            // re-evaluate auto-hide.
            scheduleAutoHide()
        case .route(let route):
            self.route = route
        case .position(let seconds):
            let clamped = max(0, seconds)
            if position != clamped { position = clamped }
            // The window slides with the stream: re-read it on every tick so
            // the badge, the scrubber and the skip bounds all follow the edge.
            refreshSeekableRange()
            advanceToNextEpisodeIfDue()
            // Cues carry source PTS and the active cue rolls with the position;
            // re-read on each tick so the overlay renders the current cue, but
            // only write when the array actually changed so unrelated
            // Observation readers (e.g. the track-selection menu) don't get
            // invalidated on every position tick.
            let cues = coordinator.engine.subtitleCues
            if subtitleCues != cues { subtitleCues = cues }
        case .duration(let seconds):
            guard duration != seconds else { break }
            duration = seconds
            // The runtime and the chapter list come from independent engine
            // publishers, so a runtime that lands *after* the chapters has to
            // re-run the marker test: `AppleChapterMarkers.intro` can only skip
            // a mislabelled single-chapter file once it knows the runtime to
            // measure the chapter against.
            refreshIntroChapter()
        case .tracks:
            // Chapters land in the same pass as the tracks, after `load`
            // returns, so this is where a stream's opening sequence becomes
            // known.
            refreshIntroChapter()
            let audio = coordinator.engine.audioTracks
            if audioTracks != audio { audioTracks = audio }
            let subtitles = coordinator.engine.subtitleTracks
            if subtitleTracks != subtitles { subtitleTracks = subtitles }
            let cues = coordinator.engine.subtitleCues
            if subtitleCues != cues { subtitleCues = cues }
            // Tracks arrive after `load`, and that is when the engine runs its
            // auto-selection — so this is where an engine-chosen track becomes
            // visible to the CC key. Only adopted when the engine reports one:
            // an engine that cannot report says nil for "off" too, and the
            // overlay's own record is the better answer there.
            if let active = coordinator.engine.activeSubtitleTrackID, selectedSubtitleID != active {
                selectedSubtitleID = active
            }
        case .failure:
            break
        }
    }

    // MARK: - Auto-hide

    func playbackPhaseChanged() { scheduleAutoHide() }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard case .playing = coordinator.phase else {
            // Keep controls visible while paused / buffering / failed.
            controlsVisible = true
            return
        }
        let delay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard case .playing = self.coordinator.phase else { return }
            self.controlsVisible = false
        }
    }

    isolated deinit {
        observationTask?.cancel()
        hideTask?.cancel()
    }
}
