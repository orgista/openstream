import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import AVFoundation
#endif

/// Previews never own the system transport controls or long-form audio session.
enum ApplePlaybackSessionPolicy: Equatable, Sendable {
    case trailer
    case playback

    enum AudioCategory: Equatable, Sendable { case ambient, playback }
    var audioCategory: AudioCategory { self == .trailer ? .ambient : .playback }
    var publishesNowPlaying: Bool { self == .playback }
    var registersRemoteCommands: Bool { self == .playback }
    // WebKit can publish its automatic audible-media session without JS metadata.
    var requiresMutedWebPlayback: Bool { self == .trailer }

    func shouldRestoreAudioSession(hasPlaybackRequest: Bool) -> Bool {
        self == .playback && hasPlaybackRequest
    }

    /// Installed at document start in every frame, including the provider iframe.
    /// WebKit's automatic audio behavior is separately constrained by ambient audio.
    var webMediaSessionSuppressionScript: String {
        guard !publishesNowPlaying, !registersRemoteCommands else { return "" }
        return """
        (() => {
          const session = navigator.mediaSession;
          if (!session) return;
          const attempt = (action) => { try { action(); } catch (_) {} };
          const setActionHandler = session.setActionHandler?.bind(session);
          const actions = ['play', 'pause', 'stop', 'seekbackward', 'seekforward',
                           'seekto', 'previoustrack', 'nexttrack'];
          const clear = () => {
            attempt(() => { session.metadata = null; });
            attempt(() => { session.playbackState = 'none'; });
            for (const action of actions) attempt(() => setActionHandler?.(action, null));
          };
          clear();
          attempt(() => Object.defineProperty(session, 'metadata', {get: () => null, set: () => {}}));
          attempt(() => Object.defineProperty(session, 'playbackState', {get: () => 'none', set: () => {}}));
          attempt(() => Object.defineProperty(session, 'setActionHandler', {
            value: (action) => { attempt(() => setActionHandler?.(action, null)); }
          }));
          attempt(() => Object.defineProperty(session, 'setPositionState', {value: () => {}}));
          document.addEventListener('play', clear, true);
          document.addEventListener('playing', clear, true);
        })();
        """
    }

    @MainActor static var activeAudioPolicy: Self? {
        didSet { audioPolicyGeneration &+= 1 }
    }
    @MainActor private static var audioPolicyGeneration: UInt64 = 0

    /// Returns once preparation is queued; activation failures are reported in the trace.
    @MainActor static func prepareTrailerAudio(
        workQueue: AppleAudioSessionWorkQueue = .shared,
        activate: @escaping @Sendable () throws -> Void
    ) {
        // Required before enqueue: a second back-to-back call must invalidate
        // this one, or the older completion could apply after the newer.
        audioPolicyGeneration &+= 1
        let generation = audioPolicyGeneration
        appleTrace("trailer audio preparing")
        // Pending long-form preparation/deactivation must finish before takeover.
        workQueue.enqueue {
            do {
                try activate()
                Task { @MainActor in
                    // A newer playback request or teardown owns any later policy change.
                    guard audioPolicyGeneration == generation else { return }
                    activeAudioPolicy = .trailer
                    appleTrace("trailer audio prepared")
                }
            } catch {
                appleTraceFailure("trailer audio unavailable: \(error.localizedDescription)")
            }
        }
    }

    /// Waits for the session to be ready; false when activation failed or was cancelled.
    @MainActor static func prepareTrailerAudioAwaiting(
        workQueue: AppleAudioSessionWorkQueue = .shared,
        activate: @escaping @Sendable () throws -> Void
    ) async -> Bool {
        audioPolicyGeneration &+= 1
        let generation = audioPolicyGeneration
        appleTrace("trailer audio preparing")
        do {
            try await workQueue.perform(activate)
        } catch {
            appleTraceFailure("trailer audio unavailable: \(error.localizedDescription)")
            return false
        }
        if audioPolicyGeneration == generation {
            activeAudioPolicy = .trailer
            appleTrace("trailer audio prepared")
        }
        return true
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    /// `pressed` is an explicit "Play Trailer": it takes `.playback` instead
    /// of the trailer's usual `.ambient`, so the silent switch does not mute
    /// the sound the viewer just asked for. Autoplay never passes it — an
    /// unrequested preview must stay silenceable exactly as the ringer
    /// switch expects.
    @MainActor static func prepareTrailerAudio(pressed: Bool = false) {
        prepareTrailerAudio(activate: trailerSessionWork(pressed: pressed))
    }

    /// Same session work, but the caller starts a player right after, so it waits.
    @MainActor static func prepareTrailerAudioAwaiting(pressed: Bool = false) async -> Bool {
        await prepareTrailerAudioAwaiting(activate: trailerSessionWork(pressed: pressed))
    }

    private static func trailerSessionWork(pressed: Bool) -> @Sendable () throws -> Void {
        {
            let policy = Self.trailer
            let session = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category = pressed
                ? .playback
                : (policy.audioCategory == .ambient ? .ambient : .playback)
            try session.setCategory(category, mode: .default, options: [])
            #if os(visionOS)
            try session.setIsNowPlayingCandidate(policy.publishesNowPlaying)
            #endif
            try session.setActive(true)
        }
    }
    #endif
}
