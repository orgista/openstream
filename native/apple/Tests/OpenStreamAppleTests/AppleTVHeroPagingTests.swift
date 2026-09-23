import Foundation
import Testing
@testable import OpenStreamApple

/// The Apple TV Discover hero's paging and cycle rules (N12).
@Suite("Apple TV hero paging")
struct AppleTVHeroPagingTests {
    @Test func theLeftStopTurnsBackAndReturnsFocusToPlay() {
        #expect(AppleTVHeroPaging.turn(for: .previousPage) == .init(offset: -1, refocus: .play))
    }

    @Test func theRightStopTurnsOnAndReturnsFocusToTheLastButton() {
        #expect(AppleTVHeroPaging.turn(for: .nextPage) == .init(offset: 1, refocus: .details))
    }

    @Test(arguments: [AppleTVHeroPaging.Target.play, .myList, .details])
    func buttonsNeverTurnThePage(_ target: AppleTVHeroPaging.Target) {
        #expect(AppleTVHeroPaging.turn(for: target) == nil)
    }

    @Test func noFocusNeverTurnsThePage() {
        #expect(AppleTVHeroPaging.turn(for: nil) == nil)
    }

    @Test func theStopsOnlyTakeFocusFromInsideTheHero() {
        #expect(AppleTVHeroPaging.stopsAreFocusable(focused: .play, pageCount: 5))
        #expect(AppleTVHeroPaging.stopsAreFocusable(focused: .nextPage, pageCount: 5))
        // Focus in the tab bar or a row: down or up can never land on a stop.
        #expect(!AppleTVHeroPaging.stopsAreFocusable(focused: nil, pageCount: 5))
    }

    @Test func oneOrNoPagesHasNothingToTurnTo() {
        #expect(!AppleTVHeroPaging.stopsAreFocusable(focused: .play, pageCount: 1))
        #expect(!AppleTVHeroPaging.stopsAreFocusable(focused: .play, pageCount: 0))
    }

    @Test func theCycleHoldsWhileTheHeroHasFocusOrItsTrailerPlays() {
        #expect(!AppleTVHeroPaging.cycleIsPaused(heroHasFocus: false, trailerIsPlaying: false))
        #expect(AppleTVHeroPaging.cycleIsPaused(heroHasFocus: true, trailerIsPlaying: false))
        #expect(AppleTVHeroPaging.cycleIsPaused(heroHasFocus: false, trailerIsPlaying: true))
    }

    @Test func turningWhilePausedKeepsTheCycleHeldWithAFreshTimer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var cycle = AppleHeroRotation.Cycle(count: 5, now: start)
        cycle.pause(at: start.addingTimeInterval(6))
        let turn = try #require(AppleTVHeroPaging.turn(for: .previousPage))
        cycle.step(by: turn.offset, at: start.addingTimeInterval(7))
        #expect(cycle.index == 4)
        #expect(cycle.isPaused)
        #expect(cycle.progress(at: start.addingTimeInterval(60)) == 0)
        #expect(cycle.dueDate == nil)
    }
}
