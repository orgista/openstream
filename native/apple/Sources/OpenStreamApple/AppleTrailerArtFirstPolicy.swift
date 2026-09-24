import Foundation

/// Trailers are art-first (owner, 2026-09-24): the metadata art always
/// draws first; the trailer is asked for only once that art is up, loads
/// behind it, and fades in only once it is really playing. A trailer that
/// is slow, stalls or fails changes nothing on screen — the art stays. No
/// spinner, no "Loading", no message, anywhere a trailer plays.
public enum AppleTrailerArtFirstPolicy {
    /// How long a pressed trailer that has not started may hold the hero's
    /// page before it quietly gives up and the art stays.
    public static let pressedTrailerGiveUp: Double = 30

    /// Where a hero's or title page's art stands.
    public enum Art: Equatable, Sendable {
        case loading, loaded, failed

        /// Loaded is for good: a later reload keeps the image it had on
        /// screen, so a failure after it does not take the trailer away.
        public func settling(with outcome: Art) -> Art {
            self == .loaded ? .loaded : outcome
        }
    }

    /// Whether the trailer's request may go out. A preview that plays by
    /// itself waits for the art to have loaded. A pressed Play Trailer waits
    /// only for the art to settle, so a title whose art fails still plays
    /// its trailer when asked instead of leaving the press dead.
    public static func mayRequestTrailer(art: Art, pressed: Bool) -> Bool {
        switch art {
        case .loading: false
        case .loaded: true
        case .failed: pressed
        }
    }

    /// What a player state message does to the video layer.
    public enum VideoLayerChange: Equatable, Sendable {
        /// Crossfade the art away over the live video.
        case reveal
        /// Crossfade back to the art.
        case returnToArt
    }

    /// The video stays hidden under the art until the page reports
    /// "revealed" — it has played real frames for a moment — and goes back
    /// under the art when it ends, pauses, errors or is blocked. Everything
    /// else ("ready", "playing", buffering) leaves the art up.
    public static func videoLayerChange(forPlayerState state: String) -> VideoLayerChange? {
        switch state {
        case "revealed": .reveal
        case "ended", "paused", "error", "autoplay-blocked", "concealed": .returnToArt
        default: nil
        }
    }

    public static let crossfadeDuration: Double = 0.6

    /// The art ↔ video crossfade; an instant swap with Reduce Motion.
    public static func crossfadeDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : crossfadeDuration
    }
}
