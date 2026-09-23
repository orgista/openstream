import Foundation
import Observation
import Testing
@testable import OpenStreamApple

/// A hero page with no backdrop drew the poster (or the placeholder) and no
/// title at all — Binnelanders on the iPhone sim, 2026-09-23 — because the
/// title rule dropped the name whenever the art was a poster.
@Suite("Hero candidates need a backdrop")
struct AppleHeroCandidateArtTests {
    private func item(_ id: String, poster: String? = nil, backdrop: String? = nil) -> AppleCatalogItem {
        AppleCatalogItem(
            mediaID: id, type: "series", name: id,
            posterURL: poster.flatMap { URL(string: "https://fixture.example/\($0)") },
            backgroundURL: backdrop.flatMap { URL(string: "https://fixture.example/\($0)") }
        )
    }

    @Test func aBackdropCounts() {
        #expect(AppleHeroRotation.hasBackdrop(item("a", poster: "p.jpg", backdrop: "b.jpg")))
    }

    @Test func noBackdropOrThePosterAgainDoesNot() {
        #expect(!AppleHeroRotation.hasBackdrop(item("a", poster: "p.jpg")))
        #expect(!AppleHeroRotation.hasBackdrop(item("a")))
        #expect(!AppleHeroRotation.hasBackdrop(item("a", poster: "p.jpg", backdrop: "p.jpg")))
    }

    @Test func titlesWithoutABackdropLeaveTheRotation() {
        let values = [
            item("a", backdrop: "a.jpg"), item("binnelanders", poster: "p.jpg"),
            item("c", backdrop: "c.jpg"), item("d")
        ]
        let picked = AppleHeroRotation.candidates(values, id: \.mediaID, hasBackdrop: AppleHeroRotation.hasBackdrop)
        #expect(picked.map(\.mediaID) == ["a", "c"])
    }

    @Test func theCapCountsOnlyTitlesWithArt() {
        // Art-less titles early in the list must not use up the five slots.
        let values = (0 ..< 4).map { item("bare\($0)") } + (0 ..< 8).map { item("art\($0)", backdrop: "\($0).jpg") }
        let picked = AppleHeroRotation.candidates(values, id: \.mediaID, hasBackdrop: AppleHeroRotation.hasBackdrop)
        #expect(picked.map(\.mediaID) == ["art0", "art1", "art2", "art3", "art4"])
    }

    @Test func repeatsAreStillDropped() {
        let values = [item("a", backdrop: "a.jpg"), item("a", backdrop: "a.jpg"), item("b", backdrop: "b.jpg")]
        let picked = AppleHeroRotation.candidates(values, id: \.mediaID, hasBackdrop: AppleHeroRotation.hasBackdrop)
        #expect(picked.map(\.mediaID) == ["a", "b"])
    }

    @Test func withNoArtAnywhereTheRotationIsKeptAsItWas() {
        let values = (0 ..< 7).map { item("bare\($0)", poster: "\($0).jpg") }
        let picked = AppleHeroRotation.candidates(values, id: \.mediaID, hasBackdrop: AppleHeroRotation.hasBackdrop)
        #expect(picked.map(\.mediaID) == AppleHeroRotation.candidates(values, id: \.mediaID).map(\.mediaID))
        #expect(picked.count == AppleHeroRotation.maximumCandidates)
    }
}

/// The hero's title slot is never empty.
@Suite("Hero title is always shown")
struct AppleHeroTitlePolicyTests {
    private let mark = URL(string: "https://fixture.example/logo.png")!
    private let other = URL(string: "https://fixture.example/other.png")!

    @Test func noWordmarkDrawsTheNameStraightAway() {
        #expect(AppleHeroTitlePolicy.presentation(wordmark: nil, loaded: nil, failed: nil, graceExpired: false) == .name)
        #expect(AppleHeroTitlePolicy.presentation(wordmark: nil, loaded: nil, failed: nil, graceExpired: true) == .name)
    }

    @Test func aFailedWordmarkDrawsTheName() {
        #expect(AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: nil, failed: mark, graceExpired: false) == .name)
    }

    @Test func aLoadedWordmarkIsDrawnAlone() {
        let shown = AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: mark, failed: nil, graceExpired: true)
        #expect(shown == .wordmark(mark))
        #expect(!shown.showsName)
    }

    @Test func aSlowWordmarkGetsTheNameOnceTheGraceIsOver() {
        let early = AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: nil, failed: nil, graceExpired: false)
        #expect(early == .wordmark(mark))
        let late = AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: nil, failed: nil, graceExpired: true)
        #expect(late == .nameWhileLoading(mark))
        #expect(late.showsName)
        // …and the mark keeps loading, to take over when it lands.
        #expect(late.wordmarkURL == mark)
    }

    @Test func anotherPagesResultsDoNotCount() {
        #expect(AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: other, failed: nil, graceExpired: true)
            == .nameWhileLoading(mark))
        #expect(AppleHeroTitlePolicy.presentation(wordmark: mark, loaded: nil, failed: other, graceExpired: false)
            == .wordmark(mark))
    }

    @Test func theGraceIsShort() {
        #expect(AppleHeroTitlePolicy.loadingGrace > 0)
        #expect(AppleHeroTitlePolicy.loadingGrace < 1)
    }
}

/// The iPhone hero's "Resume S1, E3" read the playback store directly, which
/// nothing observes, so it stayed stale after playback until the page changed.
@MainActor
@Suite("Hero Resume label follows saved progress")
struct AppleHeroResumeLabelTests {
    @Test func aSaveInvalidatesAReaderOfTheFeed() async throws {
        let suiteName = "openstream-hero-resume-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ApplePlaybackStore(defaults: defaults)
        let feed = ApplePlaybackProgressFeed.shared
        let mediaID = "tt0000001"

        try await confirmation("the reader is told") { told in
            let before = withObservationTracking {
                feed.progress(for: mediaID, in: store)
            } onChange: {
                told()
            }
            #expect(before == nil)
            #expect(AppleBillboardCopy.playTitle(progress: before, type: "series") == "Play")

            store.save(mediaID: mediaID, position: 600, duration: 2_400, partID: "tt0000001:1:3")
            let after = try #require(feed.progress(for: mediaID, in: store))
            #expect(AppleBillboardCopy.playTitle(progress: after, type: "series") == "Resume S1, E3")
        }
    }

    @Test func aClearMovesTheFeedToo() throws {
        let suiteName = "openstream-hero-resume-clear-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ApplePlaybackStore(defaults: defaults)
        store.save(mediaID: "tt0000002", position: 600, duration: 2_400)
        let revision = ApplePlaybackProgressFeed.shared.revision
        store.clear(mediaID: "tt0000002")
        #expect(ApplePlaybackProgressFeed.shared.revision != revision)
        #expect(AppleBillboardCopy.playTitle(
            progress: ApplePlaybackProgressFeed.shared.progress(for: "tt0000002", in: store), type: "movie") == "Play")
    }
}
