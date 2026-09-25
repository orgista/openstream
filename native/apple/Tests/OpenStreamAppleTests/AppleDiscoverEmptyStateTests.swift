import Testing
@testable import OpenStreamApple

/// N54 #14: with sources whose catalog could not be read, Discover said only
/// "Nothing to Show" and offered only Settings.
@Suite("Discover empty state")
struct AppleDiscoverEmptyStateTests {
    @Test("No sources is still No Sources, whatever else failed")
    func noSourcesWins() {
        let state = AppleDiscoverEmptyState(sourceCount: 0, catalogFailureCount: 3, hasSourceError: true)
        #expect(state == .noSources)
        #expect(state.title == "No Sources")
        #expect(state.offersRetry == false)
    }

    @Test(
        "A failed catalog read or an unreadable source says so and offers a reload",
        arguments: [(failures: 1, sourceError: false), (failures: 0, sourceError: true), (failures: 2, sourceError: true)]
    )
    func failureIsNamed(failures: Int, sourceError: Bool) {
        let state = AppleDiscoverEmptyState(sourceCount: 1, catalogFailureCount: failures, hasSourceError: sourceError)
        #expect(state == .couldNotLoad)
        #expect(state.title == "Couldn't Load Your Catalogs")
        #expect(state.offersRetry)
    }

    @Test("Sources that loaded but hold nothing keep Nothing to Show, with no retry")
    func emptyButHealthy() {
        let state = AppleDiscoverEmptyState(sourceCount: 2, catalogFailureCount: 0, hasSourceError: false)
        #expect(state == .nothingToShow)
        #expect(state.title == "Nothing to Show")
        #expect(state.offersRetry == false)
    }
}
