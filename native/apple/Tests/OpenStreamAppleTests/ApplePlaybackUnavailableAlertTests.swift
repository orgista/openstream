import Foundation
import Testing
@testable import OpenStreamApple

/// Every stream of a press failed before anything played (SNL S51E7 on the
/// Native player, all MKV, Apple TV check 2026-10-01): what the title page's
/// "Playback Unavailable" alert says and offers.
@Suite struct ApplePlaybackUnavailableAlertTests {
    private let noVideoTrack = ApplePlaybackFailure(kind: .unsupportedMedia,
        message: "This stream uses a format OpenStream cannot play on this device.")

    @Test func nativeWithSkippedStreamsOffersTheOpenStreamPlayer() throws {
        let alert = try #require(ApplePlaybackUnavailableAlert(failure: noVideoTrack, engine: .native,
            streamsSkippedForEngine: 6, isEpisode: true))
        #expect(alert.offersOpenStreamPlayer)
        #expect(alert.message == "None of the sources for this episode play in the Native player.")
        let film = try #require(ApplePlaybackUnavailableAlert(failure: noVideoTrack, engine: .native,
            streamsSkippedForEngine: 1, isEpisode: false))
        #expect(film.message == "None of the sources for this title play in the Native player.")
    }

    @Test func nativeWithNothingSkippedKeepsTheFailureAndOffersOKOnly() throws {
        let alert = try #require(ApplePlaybackUnavailableAlert(failure: noVideoTrack, engine: .native,
            streamsSkippedForEngine: 0, isEpisode: true))
        #expect(!alert.offersOpenStreamPlayer)
        #expect(alert.message == noVideoTrack.message)
    }

    @Test(arguments: [0, 3])
    func openStreamEngineFailingShowsTheFailureWithOKOnly(skipped: Int) throws {
        let failure = ApplePlaybackFailure(kind: .unsupportedMedia,
            message: "None of the 3 streams for this title plays on this device.")
        let alert = try #require(ApplePlaybackUnavailableAlert(failure: failure, engine: .openStream,
            streamsSkippedForEngine: skipped, isEpisode: true))
        #expect(!alert.offersOpenStreamPlayer)
        #expect(alert.message == failure.message)
    }

    @Test func aCancelledLoadShowsNoAlert() {
        let cancelled = ApplePlaybackFailure(kind: .cancelled, message: "Playback was cancelled.")
        #expect(ApplePlaybackUnavailableAlert(failure: cancelled, engine: .native,
            streamsSkippedForEngine: 6, isEpisode: true) == nil)
    }
}
