import Foundation
import Testing
@testable import OpenStreamApple

@Suite struct ApplePlaybackFailureRecoveryTests {
    private func recovery(_ kind: ApplePlaybackFailure.Kind) -> ApplePlaybackFailureRecovery {
        ApplePlaybackFailureRecovery(ApplePlaybackFailure(kind: kind, message: "x"))
    }

    @Test(arguments: [ApplePlaybackFailure.Kind.network, .timedOut, .player, .sourceEnded])
    func failuresThatCanEndDifferentlyOfferRetry(kind: ApplePlaybackFailure.Kind) {
        #expect(recovery(kind) == .retry)
    }

    @Test(arguments: [ApplePlaybackFailure.Kind.unavailable, .unsupportedMedia, .authentication])
    func failuresThatRepeatUntilASourceChangesOfferSources(kind: ApplePlaybackFailure.Kind) {
        #expect(recovery(kind) == .sources)
    }

    @Test(arguments: [ApplePlaybackFailure.Kind.engineUnavailable, .cancelled])
    func failuresNobodyCanFixFromTheTitlePageOfferOnlyClose(kind: ApplePlaybackFailure.Kind) {
        #expect(recovery(kind) == .closeOnly)
    }

    /// A failure the no-data simulator produced in the crawl: a title whose
    /// every source was ruled out.
    @Test func noUsableSourceIsNotRetryable() {
        let allRuledOut = ApplePlaybackFailure.classify(AppleLibrarySourceError.noMedia)
        #expect(allRuledOut.kind == .unavailable)
        #expect(allRuledOut.message == AppleLibrarySourceError.noMedia.localizedDescription)
        #expect(ApplePlaybackFailureRecovery(allRuledOut) == .sources)
    }

    @Test func rejectedAccountIsNotRetryable() {
        let rejected = ApplePlaybackFailure.classify(AppleIPTVError.requestFailed(401))
        #expect(ApplePlaybackFailureRecovery(rejected) == .sources)
    }

    @Test func unreachableServerIsRetryable() {
        let timedOut = ApplePlaybackFailure.classify(URLError(.timedOut))
        #expect(ApplePlaybackFailureRecovery(timedOut) == .retry)

        let serverError = ApplePlaybackFailure.classify(AppleIPTVError.requestFailed(503))
        #expect(ApplePlaybackFailureRecovery(serverError) == .retry)
    }

    @Test func retryKeepsItsLoadingStateForTheMinimumBeforeANewFailure() {
        let minimum = ApplePlaybackFailureRecovery.retryFeedbackMinimum
        #expect(minimum > .zero)
        #expect(ApplePlaybackFailureRecovery.remainingRetryFeedback(elapsed: .zero) == minimum)
        #expect(ApplePlaybackFailureRecovery.remainingRetryFeedback(elapsed: .milliseconds(250))
            == minimum - .milliseconds(250))
        #expect(ApplePlaybackFailureRecovery.remainingRetryFeedback(elapsed: minimum) == .zero)
        #expect(ApplePlaybackFailureRecovery.remainingRetryFeedback(elapsed: .seconds(30)) == .zero)
    }
}
