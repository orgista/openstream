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

    /// Installed at document start in every frame, including the provider iframe.
    /// WebKit's automatic audio behavior is separately constrained by ambient audio.
    var webMediaSessionSuppressionScript: String {
        guard !publishesNowPlaying, !registersRemoteCommands else { return "" }
        return """
        (() => {
          const session = navigator.mediaSession;
          if (!session) return;
          session.metadata = null;
          session.playbackState = 'none';
          Object.defineProperty(session, 'metadata', {get: () => null, set: () => {}});
          Object.defineProperty(session, 'playbackState', {get: () => 'none', set: () => {}});
          Object.defineProperty(session, 'setActionHandler', {value: () => {}});
          Object.defineProperty(session, 'setPositionState', {value: () => {}});
        })();
        """
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    @MainActor static func prepareTrailerAudio() -> Bool {
        let policy = Self.trailer
        let session = AVAudioSession.sharedInstance()
        do {
            let category: AVAudioSession.Category = policy.audioCategory == .ambient ? .ambient : .playback
            try session.setCategory(category, mode: .default, options: [])
            #if os(visionOS)
            try session.setIsNowPlayingCandidate(policy.publishesNowPlaying)
            #endif
            try session.setActive(true)
            return true
        } catch {
            appleTraceFailure("trailer audio unavailable: \(error.localizedDescription)")
            return false
        }
    }
    #endif
}
