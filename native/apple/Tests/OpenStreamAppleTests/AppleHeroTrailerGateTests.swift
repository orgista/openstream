import Foundation
import Testing
@testable import OpenStreamApple

/// Owner 2026-10-14: the iPhone hero's trailers are back, on the Apple TV
/// app's rules (REA report §1): muted autoplay once the still has settled,
/// stopped whenever the hero can't be seen.
@Suite struct AppleHeroTrailerGateTests {
    @Test func autoplayRunsWhenEverythingAllowsIt() {
        #expect(AppleHeroTrailerGate.plays(.init()))
    }

    @Test(arguments: [
        AppleHeroTrailerGate.Conditions(autoPlaySetting: false),
        AppleHeroTrailerGate.Conditions(reduceMotion: true),
        AppleHeroTrailerGate.Conditions(lowPower: true),
        AppleHeroTrailerGate.Conditions(systemVideoAutoplay: false),
        AppleHeroTrailerGate.Conditions(sceneIsActive: false),
        AppleHeroTrailerGate.Conditions(halfVisible: false),
        AppleHeroTrailerGate.Conditions(isPresented: false),
        AppleHeroTrailerGate.Conditions(isCovered: true),
        AppleHeroTrailerGate.Conditions(windowIsVisible: false),
        AppleHeroTrailerGate.Conditions(art: .loading),
        AppleHeroTrailerGate.Conditions(art: .failed),
    ])
    func autoplayStopsForEachRule(_ conditions: AppleHeroTrailerGate.Conditions) {
        #expect(!AppleHeroTrailerGate.plays(conditions))
    }

    @Test func aPressSkipsOnlyTheSettingAndTheFailedArt() {
        #expect(AppleHeroTrailerGate.plays(.init(autoPlaySetting: false, pressed: true)))
        #expect(AppleHeroTrailerGate.plays(.init(art: .failed, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(art: .loading, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(reduceMotion: true, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(lowPower: true, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(halfVisible: false, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(isCovered: true, pressed: true)))
        #expect(!AppleHeroTrailerGate.plays(.init(sceneIsActive: false, pressed: true)))
    }

    // MARK: The cycle around a trailer

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func thePageMovesOnASecondAfterItsTrailerEnds() {
        var cycle = AppleHeroRotation.Cycle(count: 3, now: start)
        // The trailer plays from 3 s to 93 s; the timer holds meanwhile.
        cycle.pause(at: start.addingTimeInterval(3))
        cycle.videoEnded(at: start.addingTimeInterval(93))
        #expect(cycle.dueDate == nil)
        cycle.resume(at: start.addingTimeInterval(93))
        #expect(cycle.dueDate == start.addingTimeInterval(93 + AppleHeroRotation.afterVideoDelay))
        #expect(AppleHeroRotation.afterVideoDelay == 1)
    }

    @Test func aRunningCycleAlsoMovesOnASecondAfterTheEnd() {
        var cycle = AppleHeroRotation.Cycle(count: 3, now: start)
        cycle.videoEnded(at: start.addingTimeInterval(2))
        #expect(cycle.dueDate == start.addingTimeInterval(3))
    }

    @Test func theLastPageStaysAfterItsTrailer() {
        var cycle = AppleHeroRotation.Cycle(count: 2, index: 1, now: start)
        cycle.videoEnded(at: start.addingTimeInterval(60))
        #expect(cycle.dueDate == nil)
    }

    @Test func noAdvanceWhileATrailerPlays() {
        #expect(AppleHeroRotation.cycleIsPaused(isTouching: false, trailerIsPlaying: true, trailerIsMuted: true))
        #expect(!AppleHeroRotation.cycleIsPaused(isTouching: false, trailerIsPlaying: false, trailerIsMuted: true))
    }

    @Test func theEndOfATrailerReachesTheCarousel() {
        var value = AppleHomeHeroTrailerStateKey.defaultValue
        let ended = UUID()
        AppleHomeHeroTrailerStateKey.reduce(value: &value) { .init(lastEnd: ended) }
        #expect(value.lastEnd == ended)
        // A page whose trailer is playing still wins.
        AppleHomeHeroTrailerStateKey.reduce(value: &value) { .init(isPlaying: true) }
        #expect(value.isPlaying)
        AppleHomeHeroTrailerStateKey.reduce(value: &value) { .init(lastEnd: UUID()) }
        #expect(value.isPlaying)
    }
}
