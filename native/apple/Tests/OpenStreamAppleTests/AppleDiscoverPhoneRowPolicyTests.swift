import Foundation
import Testing
@testable import OpenStreamApple

@Suite struct AppleDiscoverPhoneRowPolicyTests {
    @Test(arguments: [
        (0.0, 3420.0, "57 MIN LEFT"),
        (3000.0, 3480.0, "8 MIN LEFT"),
        (3590.0, 3600.0, "1 MIN LEFT"),
        (0.0, 3900.0, "1 HR 5 MIN LEFT"),
        (0.0, 7200.0, "2 HR LEFT"),
    ])
    func remainingTimeReadsLikeTheAppleTVApp(position: Double, duration: Double, expected: String) {
        #expect(AppleContinueWatchingCaption.remainingLabel(position: position, duration: duration) == expected)
    }

    @Test(arguments: [(10.0, 0.0), (10.0, .nan), (10.0, .infinity), (-1.0, 100.0), (100.0, 100.0)])
    func remainingTimeIsHiddenWhenTheLengthIsUnknown(position: Double, duration: Double) {
        #expect(AppleContinueWatchingCaption.remainingLabel(position: position, duration: duration) == nil)
    }

    @Test func subtitleNamesTheEpisodeOrSaysMovie() {
        #expect(AppleContinueWatchingCaption.subtitle(type: "series", partID: "tt0000001:1:3") == "Continue · S1, E3")
        #expect(AppleContinueWatchingCaption.subtitle(type: "series", partID: "tmdb:42:12:104") == "Continue · S12, E104")
        #expect(AppleContinueWatchingCaption.subtitle(type: "movie", partID: nil) == "Movie")
        #expect(AppleContinueWatchingCaption.subtitle(type: "series", partID: nil) == "Continue")
        #expect(AppleContinueWatchingCaption.subtitle(type: "series", partID: "tt0000001") == "Continue")
    }

    @Test func railsAlternateStillsAndPostersKeepingTheFirstRailFirst() {
        // Continue Watching, Your Library, Top Picks, Top 10 ×2, catalogue posters ×3.
        let shapes: [AppleDiscoverRailRhythm.Shape] = [.still, .poster, .still, .still, .still, .poster, .poster, .poster]
        let order = AppleDiscoverRailRhythm.order(shapes)
        #expect(order == [0, 1, 2, 5, 3, 6, 4, 7])
        #expect(order.map { shapes[$0] } == [.still, .poster, .still, .poster, .still, .poster, .still, .poster])
    }

    @Test func railsOfOneShapeKeepTheirOrder() {
        #expect(AppleDiscoverRailRhythm.order([.poster, .poster, .poster]) == [0, 1, 2])
        #expect(AppleDiscoverRailRhythm.order([.poster, .still, .still, .poster, .poster]) == [0, 1, 3, 2, 4])
        #expect(AppleDiscoverRailRhythm.order([]).isEmpty)
    }

    @Test func clampCandidatesShortenAtWordBoundaries() {
        #expect(AppleWordClamp.candidates("Why Did I Get Married Again?") == [
            "Why Did I Get Married Again?", "Why Did I Get Married…", "Why Did I Get…",
            "Why Did I…", "Why Did…", "Why…",
        ])
        #expect(AppleWordClamp.candidates("Monster: The Lizzie Borden Story").last == "Monster…")
        #expect(AppleWordClamp.candidates("Mayday") == ["Mayday"])
    }

    #if DEBUG
    @Test func fixtureHidesThePillWhenTheLengthIsUnknown() {
        #expect(AppleContinueWatchingFixture.info(index: 0, type: "series").remainingLabel == "57 MIN LEFT")
        #expect(AppleContinueWatchingFixture.info(index: 0, type: "series").subtitle == "Continue · S1, E3")
        #expect(AppleContinueWatchingFixture.info(index: 2, type: "movie").subtitle == "Movie")
        #expect(AppleContinueWatchingFixture.info(index: 3, type: "series").remainingLabel == nil)
    }
    #endif
}
