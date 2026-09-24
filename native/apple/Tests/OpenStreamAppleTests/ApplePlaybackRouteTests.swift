import Foundation
import Testing
@testable import OpenStreamApple

struct ApplePlaybackRouteTests {
    private let movie = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture")
    private let series = AppleCatalogItem(mediaID: "tt1234567", type: "series", name: "Fixture")

    private func source(_ kind: AppleSourceKind = .stremio, resources: [String] = [], enabled: Bool = true) -> AppleSource {
        var value = AppleSource(kind: kind, name: "Fixture", url: URL(string: "https://fixture.example/manifest.json")!, resources: resources)
        value.isEnabled = enabled
        return value
    }

    @Test(arguments: [["stream"], ["STREAM"], ["catalog", "Stream", "meta"]])
    func streamingAddOnIsPlayable(resources: [String]) {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: resources)]))
    }

    @Test func metadataOnlyAddOnOffersTrailer() {
        let playable = AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: ["catalog", "meta"])])
        #expect(playable == false)
        #expect(AppleTitlePagePolicy.primaryAction(type: movie.type, progress: nil, selectedEpisode: nil,
                                                 isPlayable: playable, hasTrailer: true) == .playTrailer)
    }

    @Test func disabledStreamingSourceIsNotPlayable() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: ["stream"], enabled: false)]) == false)
    }

    @Test func nonStremioSourceIsPlayable() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(.library)]))
    }

    @Test func mediaServerItemNeedsNoAddOn() {
        let item = AppleCatalogItem(mediaID: "ms:00000000-0000-0000-0000-000000000001:fixture", type: "series", name: "Fixture")
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: item, sources: [], episodesUnavailable: true))
    }

    @Test func finishedDownloadWorksWithoutSourcesOrEpisodes() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [], hasCompletedDownload: true, episodesUnavailable: true))
    }

    @Test func localGroupWorksWithoutSourcesOrEpisodes() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [], hasLocalGroup: true, episodesUnavailable: true))
    }

    @Test func seriesWithoutEpisodesCannotStream() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [source(resources: ["stream"])], episodesUnavailable: true) == false)
    }

    /// N17e: the hero's own episode lookup came back empty for a series whose
    /// title page offered Play and Download Season. The hero treats the list
    /// as unknown and falls back to the source check, so both say Play.
    @Test func heroWithAnEmptyEpisodeLookupStillPlaysFromAStreamingSource() {
        let sources = [source(resources: ["stream"])]
        let heroPlayable = AppleTitlePagePolicy.heroHasPlaybackRoute(item: series, sources: sources)
        let titlePagePlayable = AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: sources)
        #expect(heroPlayable)
        #expect(heroPlayable == titlePagePlayable)
        let heroAction = AppleTitlePagePolicy.heroPrimaryAction(
            type: series.type, progress: nil,
            selectedEpisode: AppleTitlePagePolicy.heroEpisode(item: series, progress: nil, episodes: []),
            isPlayable: heroPlayable, trailer: .none)
        #expect(heroAction == .play)
    }

    @Test func heroStillSaysDetailsWithNoWayToPlay() {
        let metadataOnly = [source(resources: ["catalog", "meta"])]
        #expect(AppleTitlePagePolicy.heroHasPlaybackRoute(item: series, sources: metadataOnly) == false)
        #expect(AppleTitlePagePolicy.heroHasPlaybackRoute(item: series, sources: [source(resources: ["stream"], enabled: false)]) == false)
        #expect(AppleTitlePagePolicy.heroHasPlaybackRoute(item: series, sources: [], hasCompletedDownload: true))
    }

    /// N17e on the iPhone sim: a metadata-only add-on. The hero says Details;
    /// the title page must not offer an enabled Play that can only fail.
    @Test func withOnlyAMetadataAddOnHeroAndTitlePageAgreeNothingPlays() {
        let metadataOnly = [source(resources: ["catalog", "meta"])]
        let route = AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: metadataOnly)
        #expect(AppleTitlePagePolicy.heroPrimaryAction(
            type: series.type, progress: nil, selectedEpisode: nil,
            isPlayable: AppleTitlePagePolicy.heroHasPlaybackRoute(item: series, sources: metadataOnly),
            trailer: .none) == .details)
        #expect(AppleTitlePagePolicy.canStartPlayback(type: series.type, hasPlaybackRoute: route,
                                                     isPreparing: false, hasSelectedEpisode: true) == false)
    }

    @Test func titlePagePlayNeedsARouteAnEpisodeAndNoWork() {
        #expect(AppleTitlePagePolicy.canStartPlayback(type: "series", hasPlaybackRoute: true, isPreparing: false, hasSelectedEpisode: true))
        #expect(AppleTitlePagePolicy.canStartPlayback(type: "series", hasPlaybackRoute: true, isPreparing: false, hasSelectedEpisode: false) == false)
        #expect(AppleTitlePagePolicy.canStartPlayback(type: "series", hasPlaybackRoute: true, isPreparing: true, hasSelectedEpisode: true) == false)
        #expect(AppleTitlePagePolicy.canStartPlayback(type: "movie", hasPlaybackRoute: true, isPreparing: false, hasSelectedEpisode: false))
        #expect(AppleTitlePagePolicy.canStartPlayback(type: "movie", hasPlaybackRoute: false, isPreparing: false, hasSelectedEpisode: false) == false)
    }

    @Test func heroResumesExactSavedEpisode() throws {
        let first = AppleStremioEpisode(id: "tt1234567:1:1", title: "First", season: 1, episode: 1, releaseInfo: nil)
        let saved = AppleStremioEpisode(id: "tt1234567:2:3", title: "Saved", season: 2, episode: 3, releaseInfo: nil)
        let progress = ApplePlaybackProgress(position: 742, duration: 3_000, partID: saved.id)
        let selected = try #require(AppleTitlePagePolicy.heroEpisode(item: series, progress: progress, episodes: [first, saved]))
        #expect(selected.id == saved.id)
        #expect(progress.resumePosition == 742)
        #expect(AppleTitlePagePolicy.primaryAction(type: "series", progress: progress, selectedEpisode: selected,
            isPlayable: AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [source(resources: ["stream"])]),
            hasTrailer: true) == .resume(episode: "S2, E3"))
    }

    @Test func mediaServerHeroRetainsResumeWithOpaqueEpisodeID() throws {
        let item = AppleCatalogItem(mediaID: "ms:00000000-0000-0000-0000-000000000001:fixture", type: "series", name: "Fixture")
        let progress = ApplePlaybackProgress(position: 742, duration: 3_000, partID: "server-episode")
        let selected = try #require(AppleTitlePagePolicy.heroEpisode(item: item, progress: progress, episodes: []))
        #expect(selected.id == progress.partID)
        #expect(AppleTitlePagePolicy.primaryAction(type: item.type, progress: progress, selectedEpisode: selected,
            isPlayable: AppleTitlePagePolicy.hasPlaybackRoute(item: item, sources: [], episodesUnavailable: true),
            hasTrailer: true) == .resume(episode: nil))
    }


    @Test func downloadedPlayLabelAgreesOnHeroAndTitlePage() {
        #expect(AppleTitlePagePolicy.PrimaryAction.play.displayTitle(hasCompletedDownload: true) == "Play Offline")
        #expect(AppleTitlePagePolicy.PrimaryAction.play.displayTitle(hasCompletedDownload: false) == "Play")
        #expect(AppleTitlePagePolicy.PrimaryAction.resume(episode: "S2, E3").displayTitle(hasCompletedDownload: true) == "Resume S2, E3")
    }


    @Test func heroChoosesSameNextUnwatchedEpisodeAsTitlePage() {
        let first = AppleStremioEpisode(id: "tt1234567:1:1", title: "First", season: 1, episode: 1, releaseInfo: nil)
        let next = AppleStremioEpisode(id: "tt1234567:1:2", title: "Next", season: 1, episode: 2, releaseInfo: nil)
        #expect(AppleTitlePagePolicy.heroEpisode(item: series, progress: nil, episodes: [first, next],
                                               completedIDs: [first.id]) == next)
        #expect(AppleTitlePagePolicy.heroEpisode(item: series, progress: nil, episodes: [first, next],
                                               localResumeEpisode: next) == next)
    }

}
