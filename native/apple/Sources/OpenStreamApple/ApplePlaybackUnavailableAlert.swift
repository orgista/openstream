import Foundation

/// The title page's "Playback Unavailable" alert for a press whose every
/// stream failed before anything played.
///
/// The player used to close on its own and the page showed nothing: its
/// failure alert and the page's were bound to the same coordinator, the
/// page's took the cover down to present itself, and the player's close reset
/// the failure it was about to show (SNL S51E7 on Native, all MKV, Apple TV
/// check 2026-10-01). The player now hands the failure to the page, which
/// closes the player and shows this alert.
///
/// On the Native (stock) player the streams it cannot open are passed over
/// unseen; when that is why nothing played, the alert says so and offers the
/// OpenStream player for this one play — the saved setting stays as it is.
public struct ApplePlaybackUnavailableAlert: Equatable, Sendable {
    public let message: String
    /// "Try OpenStream Player" beside OK.
    public let offersOpenStreamPlayer: Bool

    public init(message: String, offersOpenStreamPlayer: Bool) {
        self.message = message
        self.offersOpenStreamPlayer = offersOpenStreamPlayer
    }

    /// Nil for a cancelled load, which is never shown.
    public init?(
        failure: ApplePlaybackFailure,
        engine: ApplePlaybackEngineKind,
        streamsSkippedForEngine: Int,
        isEpisode: Bool
    ) {
        guard failure.kind != .cancelled else { return nil }
        if engine == .native, streamsSkippedForEngine > 0 {
            self.init(
                message: "None of the sources for this \(isEpisode ? "episode" : "title") play in the Native player.",
                offersOpenStreamPlayer: true)
        } else {
            self.init(message: failure.message, offersOpenStreamPlayer: false)
        }
    }
}
