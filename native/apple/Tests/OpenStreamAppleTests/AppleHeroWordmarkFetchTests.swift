import Foundation
import Testing
@testable import OpenStreamApple

/// Owner 2026-09-29: on a fresh install Discover's hero drew "JEOPARDY!" as
/// plain text all session while its title page had the logo. A mark found
/// late draws the next time the page comes round.
@Suite("Hero wordmark fetch")
struct AppleHeroWordmarkFetchTests {
    private let mark = URL(string: "https://fixture.example/logo.png")!

    /// The name keeps the slot for the rest of that showing, and lets go
    /// when the hero moves to another page, so the mark draws next time.
    @Test func theNameLatchLastsOneShowingOfOnePage() {
        #expect(AppleHeroTitlePolicy.nameLatch("a", from: "a", to: "a") == "a")
        #expect(AppleHeroTitlePolicy.nameLatch("a", from: "a", to: "b") == nil)
        #expect(AppleHeroTitlePolicy.nameLatch("a", from: "b", to: "a") == nil)
        #expect(AppleHeroTitlePolicy.nameLatch(nil, from: "a", to: "b") == nil)
    }

    /// Back on the page with a mark known and no latch, the mark draws.
    @Test func aPageComingRoundAgainDrawsTheMarkFoundMeanwhile() {
        let latch = AppleHeroTitlePolicy.nameLatch("a", from: "b", to: "a")
        let presentation = AppleHeroTitlePolicy.presentation(
            wordmark: mark, loaded: nil, failed: nil, graceExpired: false,
            lookupPending: false, nameShown: latch == "a"
        )
        #expect(presentation == .wordmark(mark))
    }
}
