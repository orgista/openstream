import Testing
@testable import OpenStreamApple

/// Trailers are art-first (owner, 2026-09-24): art, then — maybe — video.
@Suite struct AppleTrailerArtFirstPolicyTests {
    typealias Policy = AppleTrailerArtFirstPolicy

    @Test(arguments: [false, true])
    func noTrailerIsAskedForWhileTheArtIsLoading(pressed: Bool) {
        #expect(Policy.mayRequestTrailer(art: .loading, pressed: pressed) == false)
    }

    @Test(arguments: [false, true])
    func theTrailerIsAskedForOnceTheArtHasLoaded(pressed: Bool) {
        #expect(Policy.mayRequestTrailer(art: .loaded, pressed: pressed))
    }

    @Test func failedArtStillPlaysAPressedTrailerButNeverAutoplays() {
        #expect(Policy.mayRequestTrailer(art: .failed, pressed: true))
        #expect(Policy.mayRequestTrailer(art: .failed, pressed: false) == false)
    }

    @Test func loadedArtStaysLoadedThroughALaterFailure() {
        #expect(Policy.Art.loaded.settling(with: .failed) == .loaded)
        #expect(Policy.Art.loading.settling(with: .loaded) == .loaded)
        #expect(Policy.Art.loading.settling(with: .failed) == .failed)
        #expect(Policy.Art.failed.settling(with: .loaded) == .loaded)
    }

    @Test(arguments: ["ready", "playing", "iframe-state-1", "iframe-state-3", "muted", "unmuted"])
    func theVideoStaysHiddenUntilItIsRevealed(state: String) {
        #expect(Policy.videoLayerChange(forPlayerState: state) == nil)
    }

    @Test func aRevealedVideoCrossfadesIn() {
        #expect(Policy.videoLayerChange(forPlayerState: "revealed") == .reveal)
    }

    @Test(arguments: ["ended", "paused", "error", "autoplay-blocked", "concealed", Policy.webContentTerminatedState])
    func anEndedOrFailedVideoGoesBackToTheArt(state: String) {
        #expect(Policy.videoLayerChange(forPlayerState: state) == .returnToArt)
    }

    /// N22b: a crashed WebContent process (iPad sim, 2026-09-23) drops the
    /// video layer for good, as an error does — never a blank frame.
    @Test(arguments: ["error", "autoplay-blocked", Policy.webContentTerminatedState])
    func aDeadTrailerDropsItsVideoLayer(state: String) {
        #expect(Policy.dropsVideoLayer(forPlayerState: state))
    }

    @Test(arguments: ["ready", "revealed", "ended", "paused", "concealed"])
    func aLiveOrEndedTrailerKeepsItsVideoLayer(state: String) {
        #expect(Policy.dropsVideoLayer(forPlayerState: state) == false)
    }

    @Test func theTerminationStateIsNotOneThePageSends() {
        #expect(Policy.webContentTerminatedState == "web-content-terminated")
    }

    @Test func theCrossfadeIsSixTenthsOfASecondAndInstantWithReduceMotion() {
        #expect(Policy.crossfadeDuration(reduceMotion: false) == 0.6)
        #expect(Policy.crossfadeDuration(reduceMotion: true) == 0)
    }
}
