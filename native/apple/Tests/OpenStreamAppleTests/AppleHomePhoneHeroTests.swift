import CoreGraphics
import Foundation
import Testing
@testable import OpenStreamApple

/// The iPhone portrait hero after the Apple TV app (owner 2026-09-22): a cycle
/// that can be swiped, jumped and held, shrinking page dots, a resume button
/// read from the saved position, and a badge only from real episode dates.
@Suite("iPhone hero cycle")
struct AppleHeroRotationCycleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func theTimerFillsOverOneInterval() {
        let cycle = AppleHeroRotation.Cycle(count: 3, interval: 12, now: start)
        #expect(cycle.progress(at: start) == 0)
        #expect(cycle.progress(at: start.addingTimeInterval(6)) == 0.5)
        #expect(cycle.progress(at: start.addingTimeInterval(30)) == 1)
        #expect(cycle.dueDate == start.addingTimeInterval(12))
    }

    @Test func itAdvancesAndWrapsWhenDue() {
        var cycle = AppleHeroRotation.Cycle(count: 2, interval: 12, now: start)
        let early = cycle.advanceIfDue(at: start.addingTimeInterval(11))
        #expect(!early)
        let due = cycle.advanceIfDue(at: start.addingTimeInterval(12))
        #expect(due)
        #expect(cycle.index == 1)
        #expect(cycle.progress(at: start.addingTimeInterval(12)) == 0)
        let wrapped = cycle.advanceIfDue(at: start.addingTimeInterval(24))
        #expect(wrapped)
        #expect(cycle.index == 0)
    }

    @Test func pausingHoldsTheFillAndResumingCarriesOn() {
        var cycle = AppleHeroRotation.Cycle(count: 3, interval: 12, now: start)
        cycle.pause(at: start.addingTimeInterval(3))
        #expect(cycle.isPaused)
        #expect(cycle.dueDate == nil)
        #expect(cycle.progress(at: start.addingTimeInterval(100)) == 0.25)
        cycle.resume(at: start.addingTimeInterval(100))
        #expect(cycle.dueDate == start.addingTimeInterval(109))
        #expect(cycle.progress(at: start.addingTimeInterval(106)) == 0.75)
    }

    @Test func jumpingStartsTheNewPageFromEmpty() {
        var cycle = AppleHeroRotation.Cycle(count: 5, interval: 12, now: start)
        cycle.show(3, at: start.addingTimeInterval(8))
        #expect(cycle.index == 3)
        #expect(cycle.progress(at: start.addingTimeInterval(8)) == 0)
        cycle.step(by: -4, at: start.addingTimeInterval(9))
        #expect(cycle.index == 4)
    }

    @Test func aPausedJumpStaysPaused() {
        var cycle = AppleHeroRotation.Cycle(count: 3, interval: 12, now: start)
        cycle.pause(at: start.addingTimeInterval(5))
        cycle.show(2, at: start.addingTimeInterval(6))
        #expect(cycle.isPaused)
        #expect(cycle.progress(at: start.addingTimeInterval(60)) == 0)
    }

    @Test func oneOrNoPagesNeverMove() {
        #expect(AppleHeroRotation.Cycle(count: 1, now: start).dueDate == nil)
        var empty = AppleHeroRotation.Cycle(count: 0, now: start)
        #expect(empty.dueDate == nil)
        empty.step(by: 1, at: start)
        #expect(empty.index == 0)
    }

    @Test func anOutOfRangeStartIsClamped() {
        #expect(AppleHeroRotation.Cycle(count: 3, index: 9, now: start).index == 2)
    }

    @Test(arguments: [
        (touching: false, playing: false, muted: true, paused: false),
        (touching: true, playing: false, muted: true, paused: true),
        (touching: false, playing: true, muted: true, paused: false),
        (touching: false, playing: true, muted: false, paused: true),
        (touching: false, playing: false, muted: false, paused: false),
    ])
    func pauseRules(_ rule: (touching: Bool, playing: Bool, muted: Bool, paused: Bool)) {
        #expect(AppleHeroRotation.cycleIsPaused(
            isTouching: rule.touching, trailerIsPlaying: rule.playing, trailerIsMuted: rule.muted
        ) == rule.paused)
    }
}

@Suite("iPhone hero page dots")
struct AppleHeroPageDotsTests {
    @Test func theActivePageIsTheWideCapsule() {
        #expect(AppleHeroPageDots.size(position: 2, index: 2, count: 5) == CGSize(width: 20, height: 6))
    }

    @Test func farDotsShrinkIntoATail() {
        let widths = (0 ..< 5).map { AppleHeroPageDots.size(position: $0, index: 0, count: 5).width }
        #expect(widths == [20, 6, 6, 4.5, 3])
        let fromTheEnd = (0 ..< 5).map { AppleHeroPageDots.size(position: $0, index: 4, count: 5).width }
        #expect(fromTheEnd == [3, 4.5, 6, 6, 20])
    }

    @Test func aMiddlePageHasNoTail() {
        let widths = (0 ..< 5).map { AppleHeroPageDots.size(position: $0, index: 2, count: 5).width }
        #expect(widths == [6, 6, 20, 6, 6])
    }

    @Test func outOfRangeDotsHaveNoSize() {
        #expect(AppleHeroPageDots.size(position: 5, index: 0, count: 5) == .zero)
        #expect(AppleHeroPageDots.size(position: 0, index: 0, count: 0) == .zero)
    }
}

@Suite("iPhone hero copy")
struct AppleHomePhoneHeroCopyTests {
    @Test func aPartWatchedEpisodeNamesItself() {
        let progress = ApplePlaybackProgress(position: 600, duration: 3_000, partID: "tt1234567:1:3")
        #expect(AppleBillboardCopy.playTitle(progress: progress) == "Resume S1, E3")
    }

    @Test func aPartWatchedFilmSaysResume() {
        let progress = ApplePlaybackProgress(position: 600, duration: 6_000, partID: "tt7654321")
        #expect(AppleBillboardCopy.playTitle(progress: progress) == "Resume")
    }

    @Test func nothingToResumeSaysPlay() {
        #expect(AppleBillboardCopy.playTitle(progress: nil) == "Play")
        // Under 15 s is not a resume point, and a finished title is not either.
        #expect(AppleBillboardCopy.playTitle(progress: .init(position: 5, duration: 3_000, partID: "tt1234567:1:3")) == "Play")
        #expect(AppleBillboardCopy.playTitle(progress: .init(position: 2_990, duration: 3_000)) == "Play")
    }

    @Test func theMetadataLineLeadsWithTheKind() {
        #expect(AppleBillboardCopy.phoneMetadataLine(type: "series", genres: ["Thriller", " Drama ", "Crime"])
            == "TV Show · Thriller · Drama")
        #expect(AppleBillboardCopy.phoneMetadataLine(type: "movie", genres: nil) == "Movie")
        #expect(AppleBillboardCopy.phoneMetadataLine(type: "channel", genres: ["", " "]) == nil)
    }

    @Test func theRatingBadgeNeedsARealRating() {
        #expect(AppleBillboardCopy.ratingBadge(" TV-MA ") == "TV-MA")
        #expect(AppleBillboardCopy.ratingBadge("") == nil)
        #expect(AppleBillboardCopy.ratingBadge(nil) == nil)
        #expect(AppleBillboardCopy.ratingBadge("Not rated in this country") == nil)
    }
}

@Suite("iPhone hero badge")
struct AppleHeroBadgeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func episode(_ season: Int, _ number: Int, daysAgo: Double) -> AppleHeroBadge.Episode {
        .init(season: season, episode: number, released: now.addingTimeInterval(-daysAgo * day))
    }

    @Test func aRecentSeasonOpenerIsANewSeason() {
        let episodes = [episode(1, 1, daysAgo: 400), episode(1, 2, daysAgo: 393), episode(2, 1, daysAgo: 3)]
        #expect(AppleHeroBadge.select(type: "series", episodes: episodes, now: now) == .newSeason)
    }

    @Test func aRecentLaterEpisodeIsANewEpisode() {
        let episodes = [episode(2, 1, daysAgo: 10), episode(2, 2, daysAgo: 3), episode(2, 3, daysAgo: -4)]
        #expect(AppleHeroBadge.select(type: "series", episodes: episodes, now: now) == .newEpisode)
    }

    @Test func nothingRecentMeansNoBadge() {
        #expect(AppleHeroBadge.select(type: "series", episodes: [episode(3, 4, daysAgo: 30)], now: now) == nil)
        #expect(AppleHeroBadge.select(type: "series", episodes: [], now: now) == nil)
    }

    @Test func premieresSpecialsFilmsAndFutureEpisodesGetNothing() {
        #expect(AppleHeroBadge.select(type: "series", episodes: [episode(1, 1, daysAgo: 2)], now: now) == nil)
        #expect(AppleHeroBadge.select(type: "series", episodes: [episode(0, 3, daysAgo: 2)], now: now) == nil)
        #expect(AppleHeroBadge.select(type: "movie", episodes: [episode(2, 1, daysAgo: 2)], now: now) == nil)
        #expect(AppleHeroBadge.select(type: "series", episodes: [episode(4, 1, daysAgo: -1)], now: now) == nil)
    }

    @Test func releaseDatesReadEveryStremioShape() throws {
        let expected = try #require(AppleHeroBadge.releaseDate("2026-09-18"))
        #expect(AppleHeroBadge.releaseDate("2026-09-18T00:00:00.000Z") == expected)
        #expect(AppleHeroBadge.releaseDate("2026-09-18T00:00:00Z") == expected)
        #expect(AppleHeroBadge.releaseDate("soon") == nil)
        #expect(AppleHeroBadge.releaseDate(nil) == nil)
    }
}

@Suite("iPhone hero size")
struct AppleHomePhoneHeroLayoutTests {
    /// The owner's reference screen: an iPhone 16 Pro, 874 pt tall.
    private let iPhone16Pro = AppleHomePhoneHeroLayout(containerHeight: 874, topInset: 116, bottomInset: 83)

    private func rowPeek(_ layout: AppleHomePhoneHeroLayout) -> CGFloat {
        layout.containerHeight - layout.bottomInset - (layout.artHeight + AppleHomePhoneHeroLayout.firstRowLead)
    }

    @Test func theArtRunsToSeventyThreePercentOfTheScreen() {
        #expect(abs(iPhone16Pro.artHeight - 874 * 0.73) < 0.5)
        #expect(rowPeek(iPhone16Pro) >= AppleHomePhoneHeroLayout.minimumRowPeek)
    }

    @Test func theArtStartsAtTheTopEdge() {
        #expect(iPhone16Pro.topOverlap == 116 + AppleHomePhoneHeroLayout.stackTopPadding)
    }

    @Test func theButtonsAndDotsSitWhereTheAppleTVAppsDo() {
        let art = iPhone16Pro.artHeight
        let dots = (art - AppleHomePhoneHeroLayout.dotsCentreInset) / 874
        let button = (art - AppleHomePhoneHeroLayout.copyBottomInset - 25) / 874
        #expect(abs(dots - 0.70) < 0.01)
        #expect(abs(button - 0.64) < 0.01)
    }

    @Test(arguments: [
        // iPhone SE, 15 Pro Max, 16 Pro Max
        AppleHomePhoneHeroLayout(containerHeight: 667, topInset: 72, bottomInset: 49),
        AppleHomePhoneHeroLayout(containerHeight: 932, topInset: 118, bottomInset: 83),
        AppleHomePhoneHeroLayout(containerHeight: 956, topInset: 118, bottomInset: 83),
    ])
    func theFirstRowAlwaysPeeks(_ layout: AppleHomePhoneHeroLayout) {
        #expect(rowPeek(layout) >= AppleHomePhoneHeroLayout.minimumRowPeek)
        #expect(layout.artHeight <= layout.containerHeight * AppleHomePhoneHeroLayout.artFraction)
        #expect(layout.artHeight >= AppleHomePhoneHeroLayout.minimumArtHeight)
    }

    @Test func anUnmeasuredScrollViewGetsTheFloor() {
        #expect(AppleHomePhoneHeroLayout().artHeight == AppleHomePhoneHeroLayout.minimumArtHeight)
    }

    /// N17c: the Play button showed through the collapsed "Discover" bar.
    @Test func theCopyIsGoneBeforeItReachesTheBar() {
        let fade = AppleHomePhoneHeroLayout.copyFadeDistance
        // Resting well below the bar: full strength until the fade band.
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 400, restingTop: 400, fadeLine: 150) == 1)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 150 + fade, restingTop: 400, fadeLine: 150) == 1)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 150 + fade / 2, restingTop: 400, fadeLine: 150) == 0.5)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 150, restingTop: 400, fadeLine: 150) == 0)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 20, restingTop: 400, fadeLine: 150) == 0)
    }

    /// A short screen or a large text size puts the copy close to the bar
    /// before any scroll; it must still open at full strength.
    @Test func copyRestingCloseToTheBarStartsAtFullStrength() {
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 190, restingTop: 190, fadeLine: 150) == 1)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 170, restingTop: 190, fadeLine: 150) == 0.5)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 150, restingTop: 190, fadeLine: 150) == 0)
        // Resting at or above the line: shown at rest, gone once scrolled.
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 140, restingTop: 140, fadeLine: 150) == 1)
        #expect(AppleHomePhoneHeroLayout.copyOpacity(copyTop: 139, restingTop: 140, fadeLine: 150) == 0)
    }
}
