import Testing
@testable import OpenStreamApple

/// Live shows one loading state until its rows can show, and never sticks
/// on it or flickers to it from a failure (owner 2026-10-22).
struct AppleLiveChannelsLoadingPolicyTests {
    private func loads(rows: Bool = false, channels: Bool = false, loading: Bool = false, resolved: Bool = true,
                       failure: Bool = false, current: Bool = true) -> Bool {
        AppleLiveChannelsLoadingPolicy.showsLoading(hasRows: rows, hasChannels: channels, isLoading: loading,
            hasResolvedFirstLoad: resolved, showsFailure: failure, snapshotIsCurrent: current)
    }

    @Test func theFirstLoadShowsLoadingEvenAfterADeadPlaylistFailed() {
        #expect(loads(resolved: false))
        #expect(loads(loading: true, resolved: false, failure: true))
    }

    @Test func rowsAlwaysWin() {
        #expect(!loads(rows: true, channels: true, loading: true, resolved: false, current: false))
    }

    @Test func channelsWaitOnlyForTheirOwnSort() {
        #expect(loads(channels: true, current: false))
        // Sorted and empty (all hidden or filtered): the empty state, not a spinner.
        #expect(!loads(channels: true, current: true))
    }

    @Test func aRetryKeepsTheFailureOnScreen() {
        #expect(!loads(loading: true, failure: true))
        #expect(!loads(loading: false, failure: true))
    }

    @Test func aReloadWithNothingOnScreenLoads() {
        #expect(loads(loading: true))
        #expect(!loads(loading: false))
    }
}
